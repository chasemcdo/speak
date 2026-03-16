import AppKit
import CoreGraphics
import os

private let logger = Logger(subsystem: "com.speak.app", category: "PasteService")

/// Handles pasting transcribed text into the previously focused app.
enum PasteService {
    /// Paste the given text into the target application.
    /// Saves the current pasteboard, writes the text, simulates Cmd+V,
    /// then restores the original pasteboard after a delay.
    /// Returns `true` when paste is attempted.
    /// Returns `false` when no target app is available or the target app could not be activated.
    @discardableResult
    static func paste(_ text: String, into app: NSRunningApplication?) async -> Bool {
        // 1. Activate the target app so it receives the keystroke
        guard let app else {
            return false
        }

        app.activate()
        // Wait for the app to actually become frontmost
        var activated = false
        for _ in 0 ..< 10 {
            try? await Task.sleep(for: .milliseconds(50))
            if app.isActive {
                activated = true
                break
            }
        }

        guard activated else {
            return false
        }

        let pasteboard = NSPasteboard.general

        // 2. Save current pasteboard contents
        let previousChangeCount = pasteboard.changeCount
        let previousStrings = pasteboard.string(forType: .string)

        // 3. Write our text to the pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small extra delay to ensure the app's text field is ready
        try? await Task.sleep(for: .milliseconds(100))

        // 4. Simulate Cmd+V
        simulatePaste()

        // 5. Restore original pasteboard after the paste completes
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            // Only restore if nothing else has modified the pasteboard
            if pasteboard.changeCount == previousChangeCount + 1 {
                pasteboard.clearContents()
                if let previousStrings {
                    pasteboard.setString(previousStrings, forType: .string)
                }
            }
        }

        return true
    }

    /// Paste the given text and simulate pressing Return to submit.
    /// Used in conversation mode to submit text to Claude Code.
    @discardableResult
    static func pasteAndSubmit(_ text: String, into app: NSRunningApplication?) async -> Bool {
        let success = await paste(text, into: app)
        guard success else { return false }

        // Wait for the paste to settle before pressing Return.
        // 300ms gives the terminal time to fully process the paste.
        try? await Task.sleep(for: .milliseconds(300))

        simulateReturn()
        return true
    }

    /// Simulate a Return keystroke using CGEvent.
    private static func simulateReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Virtual key code 0x24 = Return
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            logger.warning("Failed to create CGEvent for Return keystroke")
            return
        }

        // Post at session level (like a keyboard) rather than HID level —
        // terminals handle session-level events more reliably.
        keyDown.post(tap: CGEventTapLocation.cgAnnotatedSessionEventTap)
        keyUp.post(tap: CGEventTapLocation.cgAnnotatedSessionEventTap)
    }

    /// Simulate a Cmd+V keystroke using CGEvent.
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Virtual key code 0x09 = 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return
        }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand

        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// Check if Accessibility permissions are granted (required for CGEvent posting).
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permissions.
    static func promptForAccessibility() {
        // Use the string literal to avoid concurrency-safety warning on kAXTrustedCheckOptionPrompt
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
