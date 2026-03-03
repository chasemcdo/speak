import AppKit
import Observation

/// Orchestrates the full dictation flow: hotkey → overlay → transcribe → post-process → paste.
@MainActor
@Observable
final class AppCoordinator {
    private var transcriptionEngine: any Transcribing
    private let overlayManager: any OverlayPresenting
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
    private var previewDismissTimer: DispatchWorkItem?
    private var recordingKeyMonitor: Any?
    private var previewKeyMonitor: Any?
    private var audioLevelMonitor: AudioLevelMonitor?
    private var cancelObserver: Any?
    private var confirmObserver: Any?
    private var pasteFailedHintTimer: DispatchWorkItem?

    /// Set up the coordinator with the shared app state. Call once at app launch.
    func setUp(appState: AppState, historyStore: HistoryStore) {
        self.appState = appState
        self.historyStore = historyStore

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
            }
        )

        // Listen for overlay cancel/confirm from keyboard events in the panel
        cancelObserver = NotificationCenter.default.addObserver(
            forName: .overlayCancelRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let appState = self.appState else { return }
                if appState.pasteFailedHint {
                    self.dismissPasteFailedHint()
                } else if appState.isPreviewing {
                    self.dismissPreview()
                } else if appState.isRecording {
                    await self.stopWithoutPaste()
                }
            }
        }

        confirmObserver = NotificationCenter.default.addObserver(
            forName: .overlayConfirmRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let appState = self.appState else { return }
                if appState.isPreviewing {
                    await self.pasteFromPreview()
                }
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
        Task {
            let modelManager = ModelManager()
            let locale = UserDefaults.standard.string(forKey: "locale")
                .flatMap { Locale(identifier: $0) } ?? Locale.current
            try? await modelManager.ensureModelAvailable(for: locale)
        }
    }

    /// Start a dictation session.
    func start() async {
        guard let appState, !appState.isRecording else { return }

        // Dismiss any active preview before starting a new recording
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

        // Reset state
        appState.reset()

        // Show the overlay
        overlayManager.show(appState: appState)

        // Set up audio level monitor for waveform visualization
        let monitor = AudioLevelMonitor()
        audioLevelMonitor = monitor
        transcriptionEngine.levelMonitor = monitor
        appState.audioLevel = monitor

        // Start transcription
        let locale = UserDefaults.standard.string(forKey: "locale")
            .flatMap { Locale(identifier: $0) } ?? Locale.current

        do {
            try await transcriptionEngine.startSession(appState: appState, locale: locale)
        } catch {
            appState.error = error.localizedDescription
            appState.isRecording = false
            // Dismiss the overlay so the user isn't stuck on a broken session
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

        let text = await stopAndProcess()

        // Paste if we have text
        if !text.isEmpty {
            if contextReader.hasFocusedTextField(in: previousApp) {
                // Hide overlay and paste normally
                overlayManager.hide()

                let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
                if autoPaste {
                    await pasteService.paste(text, into: previousApp)
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    previousApp?.activate()
                }
            } else {
                showPasteFailedHint(text: text)
                return
            }
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

        // Reset hotkey state in case recording was stopped via keyboard/menu
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

        // Enter preview state — overlay stays visible
        appState.isPreviewing = true
        appState.previewText = text

        // Give focus back to the previous app
        previousApp?.activate()

        // Install global key monitor for Escape/Return during preview
        installPreviewKeyMonitor()

        // Auto-dismiss after 8 seconds
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismissPreview()
            }
        }
        previewDismissTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    /// Paste the preview text and dismiss the overlay.
    func pasteFromPreview() async {
        guard let appState, appState.isPreviewing else { return }

        let text = appState.previewText
        removePreviewMonitors()

        // Paste if we have text
        if !text.isEmpty {
            if contextReader.hasFocusedTextField(in: previousApp) {
                // Hide overlay and reset state
                overlayManager.hide()
                appState.reset()

                let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
                if autoPaste {
                    await pasteService.paste(text, into: previousApp)
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    previousApp?.activate()
                }
            } else {
                appState.reset()
                showPasteFailedHint(text: text)
                return
            }
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
        await pasteService.paste(entry.processedText, into: currentApp)
    }

    // MARK: - Private

    /// Stop transcription, run post-processing, and save to history.
    /// Returns the processed text.
    private func stopAndProcess() async -> String {
        // Snapshot the paste target immediately so it can't change during async stop.
        previousApp = NSWorkspace.shared.frontmostApplication

        SoundFeedback.playStopSound()
        hotkeyManager.resetState()
        removeRecordingKeyMonitor()

        await transcriptionEngine.stopSession()
        appState?.isRecording = false
        audioLevelMonitor = nil
        appState?.audioLevel = nil
        transcriptionEngine.levelMonitor = nil

        // Read AX context after audio capture has stopped to avoid delaying it.
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

    /// Install a global key monitor for Escape/Return during recording.
    /// The overlay panel is non-activating so it never receives keyboard events;
    /// this monitor catches them from the foreground app instead.
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

    /// Remove the recording key monitor.
    private func removeRecordingKeyMonitor() {
        if let recordingKeyMonitor {
            NSEvent.removeMonitor(recordingKeyMonitor)
        }
        recordingKeyMonitor = nil
    }

    /// Install a global key monitor for Escape/Return during preview.
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

    /// Remove preview-related monitors and timers.
    private func removePreviewMonitors() {
        previewDismissTimer?.cancel()
        previewDismissTimer = nil
        if let previewKeyMonitor {
            NSEvent.removeMonitor(previewKeyMonitor)
        }
        previewKeyMonitor = nil
    }

    /// Show the paste-failed hint overlay, put text on clipboard, and auto-dismiss after 4 seconds.
    private func showPasteFailedHint(text: String) {
        guard let appState else { return }

        pasteFailedHintTimer?.cancel()
        pasteFailedHintTimer = nil

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        SoundFeedback.playPasteFailedSound()

        appState.pasteFailedHint = true
        overlayManager.show(appState: appState)

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismissPasteFailedHint()
            }
        }
        pasteFailedHintTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// Dismiss the paste-failed hint overlay.
    private func dismissPasteFailedHint() {
        guard let appState, appState.pasteFailedHint else { return }

        pasteFailedHintTimer?.cancel()
        pasteFailedHintTimer = nil
        overlayManager.hide()
        appState.reset()

        previousApp = nil
        capturedContext = nil
        capturedVocabulary = nil
    }

    /// Configure the text processing filters based on current user preferences.
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
