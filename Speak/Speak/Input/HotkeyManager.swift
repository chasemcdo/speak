import AppKit
import Carbon

/// Manages the global hotkey (fn key by default) for toggling dictation.
/// The fn key is a modifier, so we monitor flagsChanged events and detect
/// when fn is pressed and released alone (without any other keys).
final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onToggle: (() -> Void)?

    /// Track whether fn was pressed alone (no other modifiers or keys)
    private var fnKeyDown = false

    func register(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        // Monitor flagsChanged for fn key (works system-wide)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
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

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.function) && flags.subtracting(.function).isEmpty {
            // fn pressed alone (no other modifiers)
            fnKeyDown = true
        } else if fnKeyDown && !flags.contains(.function) {
            // fn released — and it was pressed alone
            fnKeyDown = false
            onToggle?()
        } else {
            // Another modifier was added while fn was held, cancel
            fnKeyDown = false
        }
    }

    deinit {
        unregister()
    }
}
