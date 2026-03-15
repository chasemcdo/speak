import AppKit
import Observation

/// Orchestrates the hands-free conversation loop: listen → transcribe → submit → wait → speak → repeat.
@MainActor
@Observable
final class ConversationCoordinator {
    private var transcriptionEngine: any Transcribing
    private let overlayManager: any OverlayPresenting
    private let pasteService: any Pasting
    private let speechSynthesizer: any SpeechSynthesizing
    private let textProcessor = TextProcessor()
    private let socketServer = ConversationSocketServer()
    private let voiceActivityDetector = VoiceActivityDetector()

    private var appState: AppState?
    private var previousApp: NSRunningApplication?
    private var audioLevelMonitor: AudioLevelMonitor?
    @ObservationIgnored private var isTransitioning = false

    private static let defaultSilenceTimeout: TimeInterval = 1.5

    /// Phrases that exit conversation mode (checked after post-processing).
    private static let exitPhrases: Set<String> = [
        "stop conversation",
        "end conversation",
        "exit conversation",
    ]

    init(
        transcriptionEngine: any Transcribing = TranscriptionEngine(),
        overlayManager: any OverlayPresenting = OverlayManager(),
        pasteService: any Pasting = PasteServiceAdapter(),
        speechSynthesizer: any SpeechSynthesizing = SpeechSynthesizerAdapter()
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.overlayManager = overlayManager
        self.pasteService = pasteService
        self.speechSynthesizer = speechSynthesizer
    }

    func setUp(appState: AppState) {
        self.appState = appState

        socketServer.onMessage = { [weak self] message in
            guard let self, message.action == "speak" else { return }
            await self.handleSpeakMessage(message.text)
        }
    }

    // MARK: - Public API

    /// Toggle conversation mode on/off (called from triple-tap).
    func toggle() async {
        guard let appState else { return }

        if appState.isConversationMode {
            await stop()
        } else {
            await start()
        }
    }

    /// Start conversation mode.
    func start() async {
        guard let appState, !appState.isConversationMode else { return }

        // Capture the terminal app (Claude Code) as our paste target
        previousApp = NSWorkspace.shared.frontmostApplication

        appState.isConversationMode = true
        appState.conversationPhase = .listening
        overlayManager.show(appState: appState)
        socketServer.start()

        await startListening()
    }

    /// Stop conversation mode and clean up everything.
    func stop() async {
        guard let appState else { return }

        speechSynthesizer.stop()
        voiceActivityDetector.stop()
        await transcriptionEngine.stopSession()
        clearAudioLevelMonitor()

        socketServer.stop()
        overlayManager.hide()

        appState.isConversationMode = false
        appState.conversationPhase = .idle
        appState.claudeResponseText = ""
        appState.reset()

        previousApp = nil
    }

    // MARK: - Listening

    private func startListening() async {
        guard let appState else { return }

        appState.conversationPhase = .listening
        appState.reset()

        let monitor = AudioLevelMonitor()
        audioLevelMonitor = monitor
        transcriptionEngine.levelMonitor = monitor
        appState.audioLevel = monitor

        // Set up VAD
        voiceActivityDetector.silenceTimeout = Self.defaultSilenceTimeout
        voiceActivityDetector.onEvent = { [weak self] event in
            guard let self else { return }
            if event == .speechEnded {
                Task { @MainActor in
                    await self.handleSpeechEnded()
                }
            }
        }
        voiceActivityDetector.start(monitor: monitor)

        let locale = UserDefaults.standard.string(forKey: "locale")
            .flatMap { Locale(identifier: $0) } ?? Locale.current

        do {
            try await transcriptionEngine.startSession(appState: appState, locale: locale)
        } catch {
            appState.error = error.localizedDescription
            await stop()
        }
    }

    // MARK: - VAD → Transcription complete

    private func handleSpeechEnded() async {
        guard let appState, appState.isConversationMode,
              appState.conversationPhase == .listening,
              !isTransitioning else { return }

        // Only proceed if we have finalized text
        guard appState.hasText else { return }

        isTransitioning = true
        defer { isTransitioning = false }

        appState.conversationPhase = .transcribing

        // Stop transcription and VAD
        voiceActivityDetector.stop()
        await transcriptionEngine.stopSession()
        appState.isRecording = false
        clearAudioLevelMonitor()

        await submitText()
    }

    // MARK: - Submit

    private func submitText() async {
        guard let appState else { return }

        let rawText = appState.displayText
        var text = rawText

        // Post-process
        configureFilters()
        if !textProcessor.filters.isEmpty {
            let locale = UserDefaults.standard.string(forKey: "locale")
                .flatMap { Locale(identifier: $0) } ?? Locale.current
            text = await textProcessor.process(text, context: ProcessingContext(locale: locale))
        }

        // Check for exit phrases
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespaces)
        if Self.exitPhrases.contains(trimmed) {
            await stop()
            return
        }

        guard !text.isEmpty else {
            // Nothing to submit — go back to listening
            await startListening()
            return
        }

        appState.conversationPhase = .submitting

        // Paste and submit into the terminal (auto-submit regardless of user setting).
        // If paste fails, still transition to waiting — user might manually submit.
        _ = await pasteService.pasteAndSubmit(text, into: previousApp)

        appState.conversationPhase = .waitingForClaude
    }

    // MARK: - Speak response from Claude

    private func handleSpeakMessage(_ text: String) async {
        guard let appState, appState.isConversationMode else { return }

        appState.conversationPhase = .speaking
        appState.claudeResponseText = text

        await speechSynthesizer.speak(text)

        appState.claudeResponseText = ""

        // Loop back to listening
        if appState.isConversationMode {
            await startListening()
        }
    }

    // MARK: - Helpers

    private func clearAudioLevelMonitor() {
        audioLevelMonitor = nil
        appState?.audioLevel = nil
        transcriptionEngine.levelMonitor = nil
    }

    private func configureFilters() {
        textProcessor.removeAllFilters()

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "removeFillerWords") {
            textProcessor.addFilter(FillerWordFilter())
        }
        if defaults.bool(forKey: "autoFormat") {
            textProcessor.addFilter(FormattingFilter())
        }
        if defaults.bool(forKey: "llmRewrite") {
            textProcessor.addFilter(LLMRewriter())
        }
    }
}
