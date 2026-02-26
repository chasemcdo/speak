import AppKit
import CoreGraphics

/// Handles pasting transcribed text into the previously focused app.
enum PasteService {
    /// Paste the given text into the target application.
    /// Saves the current pasteboard, writes the text, simulates Cmd+V,
    /// then restores the original pasteboard after a delay.
    static func paste(_ text: String, into app: NSRunningApplication?) async {
        let pasteboard = NSPasteboard.general

        // 1. Save current pasteboard contents
        let previousChangeCount = pasteboard.changeCount
        let previousStrings = pasteboard.string(forType: .string)

        // 2. Write our text to the pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Activate the target app so it receives the keystroke
        if let app {
            app.activate()
            // Wait for the app to actually become frontmost
            for _ in 0 ..< 10 {
                try? await Task.sleep(for: .milliseconds(50))
                if app.isActive { break }
            }
        }

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
