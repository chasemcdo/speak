import AppKit

// MARK: - OverlayAction

enum OverlayAction {
    case cancel
    case confirm
    case acceptSuggestion
}

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
    var onAction: ((OverlayAction) -> Void)? { get set }
    func show(appState: AppState)
    func hide()
}

extension OverlayManager: OverlayPresenting {}

// MARK: - Pasting

@MainActor
protocol Pasting {
    @discardableResult
    func paste(_ text: String, into app: NSRunningApplication?) async -> Bool
}

@MainActor
struct PasteServiceAdapter: Pasting {
    @discardableResult
    func paste(_ text: String, into app: NSRunningApplication?) async -> Bool {
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
    func register(
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onModeChange: @escaping (RecordingMode) -> Void
    )
    func resetState()
}

extension HotkeyManager: HotkeyManaging {}

// MARK: - HistoryHotkeyManaging

protocol HistoryHotkeyManaging {
    func register(onPasteLast: @escaping () -> Void)
}

extension HistoryHotkeyManager: HistoryHotkeyManaging {}
