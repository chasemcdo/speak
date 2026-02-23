import AppKit

/// Monitors for the global Cmd+Ctrl+V hotkey to paste the last history entry.
final class HistoryHotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onPasteLast: (() -> Void)?

    func register(onPasteLast: @escaping () -> Void) {
        self.onPasteLast = onPasteLast

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    func unregister() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        onPasteLast = nil
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Virtual key code 0x09 = 'V'
        guard event.keyCode == 0x09 else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.command, .control] else { return }
        onPasteLast?()
    }

    deinit {
        unregister()
    }
}
