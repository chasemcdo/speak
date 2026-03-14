import AppKit
import Observation

/// Orchestrates the full dictation flow: hotkey → overlay → transcribe → post-process → paste.
@MainActor
@Observable
final class AppCoordinator {
    private var transcriptionEngine: any Transcribing
    private var overlayManager: any OverlayPresenting
    private let hotkeyManager: any HotkeyManaging
    private let historyHotkeyManager: any HistoryHotkeyManaging
    private let textProcessor = TextProcessor()
    private let contextReader: any ContextReading
    private let pasteService: any Pasting
    private let checkMicPermission: @MainActor () -> Bool
    private let checkSpeechAuth: @MainActor () -> Bool

    init(
        transcriptionEngine: any Transcribing = TranscriptionEngine(),
        overlayManager: any OverlayPresenting = OverlayManager(),
        hotkeyManager: any HotkeyManaging = HotkeyManager(),
        historyHotkeyManager: any HistoryHotkeyManaging = HistoryHotkeyManager(),
        contextReader: any ContextReading = ContextReader(),
        pasteService: any Pasting = PasteServiceAdapter(),
        checkMicPermission: @escaping @MainActor () -> Bool = { AudioCaptureManager.permissionGranted },
        checkSpeechAuth: @escaping @MainActor () -> Bool = { ModelManager.authorizationGranted }
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.overlayManager = overlayManager
        self.hotkeyManager = hotkeyManager
        self.historyHotkeyManager = historyHotkeyManager
        self.contextReader = contextReader
        self.pasteService = pasteService
        self.checkMicPermission = checkMicPermission
        self.checkSpeechAuth = checkSpeechAuth
    }

    private var previousApp: NSRunningApplication?
    private var capturedContext: String?
    private var capturedVocabulary: ScreenVocabulary?
    private var appState: AppState?
    private var historyStore: HistoryStore?
    private var dictionaryStore: DictionaryStore?
    private var previewDismissTask: Task<Void, Never>?
    private var recordingKeyMonitor: Any?
    private var previewKeyMonitor: Any?
    private var audioLevelMonitor: AudioLevelMonitor?
    @ObservationIgnored private var isPreparing = false
    private let modelPreloader = ModelPreloader()
    private var suggestionManager: SuggestionManager?
    private var textDelivery: TextDeliveryService?

    /// Set up the coordinator with the shared app state. Call once at app launch.
    func setUp(appState: AppState, historyStore: HistoryStore, dictionaryStore: DictionaryStore? = nil) {
        self.appState = appState
        self.historyStore = historyStore
        self.dictionaryStore = dictionaryStore

        // Set up suggestion manager
        let suggestion = SuggestionManager(
            dictionaryStore: dictionaryStore,
            overlayManager: overlayManager,
            appState: appState
        )
        suggestion.onAccepted = { [weak self] in self?.configureFilters() }
        self.suggestionManager = suggestion

        // Set up text delivery service
        let delivery = TextDeliveryService(
            pasteService: pasteService,
            overlayManager: overlayManager,
            appState: appState
        )
        delivery.onPasteSucceeded = { [weak self] text, app in
            guard let self,
                  UserDefaults.standard.bool(forKey: "autoLearnDictionary"),
                  self.dictionaryStore != nil else { return }
            self.suggestionManager?.scheduleEditDetection(pastedText: text, into: app)
        }
        self.textDelivery = delivery

        // Register the global hotkey (double-tap to toggle on, hold to transcribe)
        hotkeyManager.register(
            onStart: { [weak self] in
                Task { @MainActor in
                    await self?.start()
                }
            },
            onStop: { [weak self] in
                Task { @MainActor in
                    await self?.confirm()
                }
            },
            onModeChange: { [weak self] mode in
                Task { @MainActor in
                    self?.appState?.recordingMode = mode
                }
            }
        )

        // Wire overlay actions via closure
        overlayManager.onAction = { [weak self] action in
            Task { @MainActor in
                self?.handleOverlayAction(action)
            }
        }

        // Prewarm the LLM if the user has it enabled
        if UserDefaults.standard.bool(forKey: "llmRewrite") {
            Task {
                await LLMRewriter.prewarm()
            }
        }

        // Register Cmd+Ctrl+V to paste the last history entry
        historyHotkeyManager.register { [weak self] in
            Task { @MainActor in
                await self?.pasteLastFromHistory()
            }
        }
    }

    /// Pre-download the speech model for the user's selected locale so it's
    /// ready when they start recording.
    func preloadModel() {
        modelPreloader.preload()
    }

    /// Start a dictation session.
    func start() async {
        guard let appState, !appState.isRecording, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        let locale = UserDefaults.standard.string(forKey: "locale")
            .flatMap { Locale(identifier: $0) } ?? Locale.current
        let localeID = locale.identifier(.bcp47)

        // Cancel any pending edit detection from a prior session
        suggestionManager?.cancelEditDetection()

        // Dismiss any active suggestion or preview before starting a new recording
        if appState.suggestedWord != nil {
            suggestionManager?.dismiss()
        }
        if appState.isPreviewing {
            dismissPreview()
        }

        // Pre-check permissions before showing the overlay
        guard checkMicPermission() else {
            appState.error = AudioCaptureError.microphonePermissionDenied.localizedDescription
            return
        }
        guard checkSpeechAuth() else {
            appState.error = TranscriptionError.notAuthorized.localizedDescription
            return
        }

        // Reset state and show overlay immediately so the user gets feedback
        appState.reset()
        overlayManager.show(appState: appState)

        // Wait for the matching preload to finish before starting audio
        await modelPreloader.waitForPreload(localeID: localeID)

        // Re-check after the suspension window — another start() may have run while we were waiting
        guard !appState.isRecording else { return }

        // Cancel all preloads so they don't consume bandwidth during recording
        modelPreloader.cancelAll()

        // Set up audio level monitor for waveform visualization
        let monitor = AudioLevelMonitor()
        audioLevelMonitor = monitor
        transcriptionEngine.levelMonitor = monitor
        appState.audioLevel = monitor

        do {
            try await transcriptionEngine.startSession(appState: appState, locale: locale)
        } catch {
            appState.error = error.localizedDescription
            appState.isRecording = false
            overlayManager.hide()
            audioLevelMonitor = nil
            appState.audioLevel = nil
            transcriptionEngine.levelMonitor = nil
            return
        }

        SoundFeedback.playStartSound()
        installRecordingKeyMonitor()

        // Prewarm LLM in parallel with recording if enabled
        if UserDefaults.standard.bool(forKey: "llmRewrite") {
            Task {
                await LLMRewriter.prewarm()
            }
        }
    }

    /// Confirm and paste the transcribed text.
    func confirm() async {
        guard let appState, appState.isRecording else { return }

        let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
        let text = await stopAndProcess()

        if !text.isEmpty {
            await textDelivery?.deliver(text, autoPaste: autoPaste, into: previousApp)
        } else {
            overlayManager.hide()
            appState.reset()
        }

        previousApp = nil
        capturedContext = nil
        capturedVocabulary = nil
    }

    /// Cancel the current dictation session.
    func cancel() async {
        guard let appState, appState.isRecording else { return }

        hotkeyManager.resetState()
        removeRecordingKeyMonitor()

        await transcriptionEngine.stopSession()
        audioLevelMonitor = nil
        appState.audioLevel = nil
        transcriptionEngine.levelMonitor = nil
        appState.reset()
        overlayManager.hide()
    }

    /// Stop recording and show a preview without pasting.
    func stopWithoutPaste() async {
        guard let appState, appState.isRecording else { return }

        let text = await stopAndProcess()

        appState.isPreviewing = true
        appState.previewText = text
        previousApp?.activate()
        installPreviewKeyMonitor()

        previewDismissTask?.cancel()
        previewDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.previewAutoDismiss))
            guard !Task.isCancelled else { return }
            self?.dismissPreview()
        }
    }

    /// Paste the preview text and dismiss the overlay.
    func pasteFromPreview() async {
        guard let appState, appState.isPreviewing else { return }

        let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
        let text = appState.previewText
        removePreviewMonitors()

        if !text.isEmpty {
            appState.reset()
            await textDelivery?.deliver(text, autoPaste: autoPaste, into: previousApp)
        } else {
            overlayManager.hide()
            appState.reset()
        }

        previousApp = nil
        capturedContext = nil
        capturedVocabulary = nil
    }

    /// Dismiss the preview without pasting.
    func dismissPreview() {
        guard let appState, appState.isPreviewing else { return }

        removePreviewMonitors()
        overlayManager.hide()
        appState.reset()

        previousApp = nil
        capturedContext = nil
        capturedVocabulary = nil
    }

    /// Paste the most recent history entry into the current app.
    func pasteLastFromHistory() async {
        guard let appState, !appState.isRecording,
              let entry = historyStore?.mostRecent else { return }
        let currentApp = NSWorkspace.shared.frontmostApplication
        let success = await pasteService.paste(entry.processedText, into: currentApp)
        if !success {
            textDelivery?.showPasteFailedHint(text: entry.processedText)
        }
    }

    /// Testable entry point: surface a suggestion in the overlay.
    func handleSuggestion(_ suggestion: DictionarySuggestion) {
        suggestionManager?.show(suggestion)
    }

    // MARK: - Private

    /// Stop transcription, run post-processing, and save to history.
    private func stopAndProcess() async -> String {
        previousApp = NSWorkspace.shared.frontmostApplication

        SoundFeedback.playStopSound()
        hotkeyManager.resetState()
        removeRecordingKeyMonitor()

        await transcriptionEngine.stopSession()
        appState?.isRecording = false
        audioLevelMonitor = nil
        appState?.audioLevel = nil
        transcriptionEngine.levelMonitor = nil

        capturedContext = contextReader.readContext(from: previousApp)
        if UserDefaults.standard.bool(forKey: "screenContext") {
            capturedVocabulary = contextReader.readScreenVocabulary(from: previousApp)
        }

        let rawText = appState?.displayText ?? ""
        var text = rawText

        if !text.isEmpty {
            configureFilters()

            if !textProcessor.filters.isEmpty {
                appState?.isPostProcessing = true

                let locale = UserDefaults.standard.string(forKey: "locale")
                    .flatMap { Locale(identifier: $0) } ?? Locale.current

                let context = ProcessingContext(
                    surroundingText: capturedContext,
                    screenVocabulary: capturedVocabulary,
                    locale: locale
                )

                text = await textProcessor.process(text, context: context)
                appState?.isPostProcessing = false
            }
        }

        if !text.isEmpty {
            historyStore?.add(HistoryEntry(
                rawText: rawText,
                processedText: text,
                sourceAppName: previousApp?.localizedName,
                sourceAppBundleID: previousApp?.bundleIdentifier
            ))
        }

        return text
    }

    /// Handle an action dispatched from the overlay UI.
    private func handleOverlayAction(_ action: OverlayAction) {
        guard let appState else { return }
        switch action {
        case .cancel:
            if appState.suggestedWord != nil {
                suggestionManager?.dismiss()
            } else if appState.pasteFailedHint {
                textDelivery?.dismissPasteFailedHint()
            } else if appState.isPreviewing {
                dismissPreview()
            } else if appState.isRecording {
                Task { await stopWithoutPaste() }
            }
        case .confirm:
            if appState.isRecording {
                Task { await confirm() }
            } else if appState.isPreviewing {
                Task { await pasteFromPreview() }
            }
        case .acceptSuggestion:
            suggestionManager?.accept()
        }
    }

    private func installRecordingKeyMonitor() {
        guard recordingKeyMonitor == nil else { return }

        recordingKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, let appState = self.appState, appState.isRecording else { return }
                if event.keyCode == 53 { // Escape
                    await self.stopWithoutPaste()
                }
            }
        }
    }

    private func removeRecordingKeyMonitor() {
        if let recordingKeyMonitor {
            NSEvent.removeMonitor(recordingKeyMonitor)
        }
        recordingKeyMonitor = nil
    }

    private func installPreviewKeyMonitor() {
        guard previewKeyMonitor == nil else { return }

        previewKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.keyCode == 53 { // Escape
                    self.dismissPreview()
                } else if event.keyCode == 36 { // Return
                    await self.pasteFromPreview()
                }
            }
        }
    }

    private func removePreviewMonitors() {
        previewDismissTask?.cancel()
        previewDismissTask = nil
        if let previewKeyMonitor {
            NSEvent.removeMonitor(previewKeyMonitor)
        }
        previewKeyMonitor = nil
    }

    /// Configure the text processing filters based on current user preferences.
    private func configureFilters() {
        textProcessor.removeAllFilters()

        let defaults = UserDefaults.standard

        if defaults.bool(forKey: "removeFillerWords") {
            textProcessor.addFilter(FillerWordFilter())
        }

        if let phrases = dictionaryStore?.entries.map(\.phrase), !phrases.isEmpty {
            textProcessor.addFilter(DictionaryReplacementFilter(phrases: phrases))
        }

        if defaults.bool(forKey: "autoFormat") {
            textProcessor.addFilter(FormattingFilter())
        }

        if defaults.bool(forKey: "llmRewrite") {
            textProcessor.addFilter(LLMRewriter())
        }
    }
}
