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
    @ObservationIgnored private var waitingTimeoutTask: Task<Void, Never>?
    private let registrationChecker: () -> Bool

    /// Called when conversation mode is toggled but MCP setup hasn't been completed.
    var onSetupRequired: (() -> Void)?

    /// Called when conversation mode starts or stops, so external components
    /// (e.g. hotkey manager) can sync state.
    var onConversationModeChanged: ((Bool) -> Void)?

    private var escapeMonitor: Any?

    private static let defaultSilenceTimeout: TimeInterval = 1.5
    /// How long to wait for Claude to call the speak tool before falling back to listening.
    private static let waitingTimeout: TimeInterval = 120

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
        speechSynthesizer: any SpeechSynthesizing = SpeechSynthesizerAdapter(),
        registrationChecker: @escaping () -> Bool = { ClaudeCodeMCPRegistration.isRegistered() }
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.overlayManager = overlayManager
        self.pasteService = pasteService
        self.speechSynthesizer = speechSynthesizer
        self.registrationChecker = registrationChecker
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

        guard registrationChecker() else {
            onSetupRequired?()
            return
        }

        // Capture the terminal app (Claude Code) as our paste target
        previousApp = NSWorkspace.shared.frontmostApplication

        appState.isConversationMode = true
        appState.conversationPhase = .listening
        onConversationModeChanged?(true)
        installEscapeMonitor()
        overlayManager.show(appState: appState)
        socketServer.start()

        await startListening()
    }

    /// Stop conversation mode and clean up everything.
    func stop() async {
        guard let appState, appState.isConversationMode else { return }

        // Clear conversation state immediately to prevent races at suspension points
        appState.isConversationMode = false
        onConversationModeChanged?(false)

        waitingTimeoutTask?.cancel()
        waitingTimeoutTask = nil
        speechSynthesizer.stop()
        voiceActivityDetector.stop()
        await transcriptionEngine.stopSession()
        clearAudioLevelMonitor()

        removeEscapeMonitor()
        socketServer.stop()
        overlayManager.hide()

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
        startWaitingTimeout()
    }

    private func startWaitingTimeout() {
        waitingTimeoutTask?.cancel()
        waitingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.waitingTimeout))
            guard let self, !Task.isCancelled,
                  let appState = self.appState,
                  appState.isConversationMode,
                  appState.conversationPhase == .waitingForClaude else { return }
            // Claude didn't respond in time — loop back to listening
            await self.startListening()
        }
    }

    // MARK: - Speak response from Claude

    private func handleSpeakMessage(_ text: String) async {
        guard let appState, appState.isConversationMode else { return }
        waitingTimeoutTask?.cancel()
        waitingTimeoutTask = nil

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

    /// Install a global key monitor for Escape to exit conversation mode.
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // Escape
            Task { @MainActor in
                await self?.stop()
            }
        }
    }

    /// Remove the Escape key monitor.
    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
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
