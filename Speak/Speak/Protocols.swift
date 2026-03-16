import AppKit
import CoreAudio

// MARK: - Transcribing

@MainActor
protocol Transcribing {
    var levelMonitor: AudioLevelMonitor? { get set }
    var selectedDeviceID: AudioDeviceID? { get set }
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
    @discardableResult
    func paste(_ text: String, into app: NSRunningApplication?) async -> Bool
    @discardableResult
    func pasteAndSubmit(_ text: String, into app: NSRunningApplication?) async -> Bool
}

@MainActor
struct PasteServiceAdapter: Pasting {
    @discardableResult
    func paste(_ text: String, into app: NSRunningApplication?) async -> Bool {
        await PasteService.paste(text, into: app)
    }

    @discardableResult
    func pasteAndSubmit(_ text: String, into app: NSRunningApplication?) async -> Bool {
        await PasteService.pasteAndSubmit(text, into: app)
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
    var isConversationMode: Bool { get set }
    func register(
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onModeChange: @escaping (RecordingMode) -> Void,
        onConversationToggle: @escaping () -> Void
    )
    func resetState()
}

extension HotkeyManager: HotkeyManaging {}

// MARK: - HistoryHotkeyManaging

protocol HistoryHotkeyManaging {
    func register(onPasteLast: @escaping () -> Void)
}

extension HistoryHotkeyManager: HistoryHotkeyManaging {}

// MARK: - SpeechSynthesizing

@MainActor
protocol SpeechSynthesizing {
    func speak(_ text: String) async
    func stop()
    var isSpeaking: Bool { get }
}

@MainActor
struct SpeechSynthesizerAdapter: SpeechSynthesizing {
    private let service = SpeechSynthesizerService()

    func speak(_ text: String) async {
        await service.speak(text)
    }

    func stop() {
        service.stop()
    }

    var isSpeaking: Bool {
        service.isSpeaking
    }
}
