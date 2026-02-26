import AppKit

// MARK: - Transcribing

@MainActor
protocol Transcribing {
    var levelMonitor: AudioLevelMonitor? { get set }
    func startSession(appState: AppState, locale: Locale) async throws
    func stopSession() async
}

extension TranscriptionEngine: Transcribing {}

// MARK: - OverlayPresenting

@MainActor
protocol OverlayPresenting {
    func show(appState: AppState)
    func hide()
}

extension OverlayManager: OverlayPresenting {}

// MARK: - Pasting

@MainActor
protocol Pasting {
    func paste(_ text: String, into app: NSRunningApplication?) async
}

@MainActor
struct PasteServiceAdapter: Pasting {
    func paste(_ text: String, into app: NSRunningApplication?) async {
        await PasteService.paste(text, into: app)
    }
}

// MARK: - ContextReading

@MainActor
protocol ContextReading {
    func readContext(from app: NSRunningApplication?) -> String?
    func readScreenVocabulary(from app: NSRunningApplication?) -> ScreenVocabulary?
    func hasFocusedTextField(in app: NSRunningApplication?) -> Bool
}

extension ContextReader: ContextReading {}

// MARK: - HotkeyManaging

protocol HotkeyManaging {
    func register(onStart: @escaping () -> Void, onStop: @escaping () -> Void)
    func resetState()
}

extension HotkeyManager: HotkeyManaging {}

// MARK: - HistoryHotkeyManaging

protocol HistoryHotkeyManaging {
    func register(onPasteLast: @escaping () -> Void)
}

extension HistoryHotkeyManager: HistoryHotkeyManaging {}
