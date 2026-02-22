import AppKit
import Carbon

/// Manages the global hotkey (⌥Space by default) for toggling dictation.
final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onToggle: (() -> Void)?

    /// The key code and modifier flags for the hotkey.
    /// Default: Option + Space (keyCode 49 = space, modifierFlags = option)
    var keyCode: UInt16 = 49
    var modifierFlags: NSEvent.ModifierFlags = .option

    func register(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        // Monitor key events when Speak is NOT the active app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Monitor key events when Speak IS the active app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotkeyEvent(event) == true {
                self?.onToggle?()
                return nil // consume the event
            }
            return event
        }
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        onToggle = nil
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if isHotkeyEvent(event) {
            onToggle?()
        }
    }

    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        // Check key code matches
        guard event.keyCode == keyCode else { return false }

        // Check that the required modifier is present
        // Use intersection to ignore unrelated modifiers like caps lock
        let required = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let actual = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return actual == required
    }

    deinit {
        unregister()
    }
}
