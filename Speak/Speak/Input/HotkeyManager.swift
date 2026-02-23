import AppKit
import Carbon

/// The modifier key used to toggle dictation.
enum TranscriptionHotkey: String, CaseIterable {
    case fn
    case control
    case option
    case command

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .control: return .control
        case .option: return .option
        case .command: return .command
        }
    }

    var label: String {
        switch self {
        case .fn: return "fn"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        }
    }

    var shortLabel: String {
        switch self {
        case .fn: return "fn"
        case .control: return "⌃"
        case .option: return "⌥"
        case .command: return "⌘"
        }
    }

    /// The currently configured hotkey, read from UserDefaults.
    static var current: TranscriptionHotkey {
        TranscriptionHotkey(rawValue: UserDefaults.standard.string(forKey: "hotkeyModifier") ?? "") ?? .fn
    }
}

/// Manages the global hotkey for toggling dictation.
/// The hotkey is a modifier key, so we monitor flagsChanged events and detect
/// when it is pressed and released alone (without any other keys).
final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onToggle: (() -> Void)?

    /// Track whether the hotkey modifier was pressed alone (no other modifiers or keys)
    private var hotkeyDown = false

    func register(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        // Monitor flagsChanged for the configured modifier key (works system-wide)
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
        let hotkey = TranscriptionHotkey.current

        if flags.contains(hotkey.modifierFlag) && flags.subtracting(hotkey.modifierFlag).isEmpty {
            // Hotkey modifier pressed alone (no other modifiers)
            hotkeyDown = true
        } else if hotkeyDown && !flags.contains(hotkey.modifierFlag) {
            // Hotkey modifier released — and it was pressed alone
            hotkeyDown = false
            onToggle?()
        } else {
            // Another modifier was added while hotkey was held, cancel
            hotkeyDown = false
        }
    }

    deinit {
        unregister()
    }
}
