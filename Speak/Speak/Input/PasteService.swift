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
            // Brief pause to let the app come to front
            try? await Task.sleep(for: .milliseconds(150))
        }

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
        let source = CGEventSource(stateID: .hidEventState)

        // Virtual key code 0x09 = 'v'
        guard let keyDown = CGEvent(keyboardEventType: .keyDown, virtualKey: 0x09, keyIsDown: true),
              let keyUp = CGEvent(keyboardEventType: .keyUp, virtualKey: 0x09, keyIsDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Check if Accessibility permissions are granted (required for CGEvent posting).
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permissions.
    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
