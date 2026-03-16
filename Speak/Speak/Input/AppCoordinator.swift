import AppKit
import Observation

/// Orchestrates the full dictation flow: hotkey → overlay → transcribe → post-process → paste.
@MainActor
@Observable
final class AppCoordinator {
    private var transcriptionEngine: any Transcribing
    private let overlayManager: any OverlayPresenting
    private var hotkeyManager: any HotkeyManaging
    private let historyHotkeyManager: any HistoryHotkeyManaging
    private let textProcessor = TextProcessor()
    private let contextReader: any ContextReading
    private let pasteService: any Pasting
    private let checkMicPermission: @MainActor () -> Bool
    private let checkSpeechAuth: @MainActor () -> Bool
    private(set) var audioDeviceManager: AudioDeviceManager?

    init(
        transcriptionEngine: any Transcribing = TranscriptionEngine(),
        overlayManager: any OverlayPresenting = OverlayManager(),
        hotkeyManager: any HotkeyManaging = HotkeyManager(),
        historyHotkeyManager: any HistoryHotkeyManaging = HistoryHotkeyManager(),
        contextReader: any ContextReading = ContextReader(),
        pasteService: any Pasting = PasteServiceAdapter(),
        checkMicPermission: @escaping @MainActor () -> Bool = { AudioCaptureManager.permissionGranted },
        checkSpeechAuth: @escaping @MainActor () -> Bool = { ModelManager.authorizationGranted },
        audioDeviceManager: AudioDeviceManager? = nil
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.overlayManager = overlayManager
        self.hotkeyManager = hotkeyManager
        self.historyHotkeyManager = historyHotkeyManager
        self.contextReader = contextReader
        self.pasteService = pasteService
        self.checkMicPermission = checkMicPermission
        self.checkSpeechAuth = checkSpeechAuth
        self.audioDeviceManager = audioDeviceManager
    }

    /// Sync conversation mode state to the hotkey manager so it can handle
    /// single-press exit from conversation mode.
    func setConversationMode(_ active: Bool) {
        hotkeyManager.isConversationMode = active
    }

    private var previousApp: NSRunningApplication?
    private var capturedContext: String?
    private var capturedVocabulary: ScreenVocabulary?
    private var appState: AppState?
    private var historyStore: HistoryStore?
    private var previewDismissTimer: DispatchWorkItem?
    private var pasteFailedHintTimer: DispatchWorkItem?
    private var recordingKeyMonitor: Any?
    private var previewKeyMonitor: Any?
    private var audioLevelMonitor: AudioLevelMonitor?
    private var cancelObserver: Any?
    private var confirmObserver: Any?
    private var preloadTasksByLocale: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var isPreparing = false
    private let modelManager = ModelManager()

    /// Set up the coordinator with the shared app state. Call once at app launch.
    func setUp(appState: AppState, historyStore: HistoryStore, onConversationToggle: @escaping () -> Void = {}) {
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
            },
            onModeChange: { [weak self] mode in
                Task { @MainActor in
                    self?.appState?.recordingMode = mode
                }
            },
            onConversationToggle: {
                Task { @MainActor in
                    onConversationToggle()
                }
            }
        )

        installOverlayObservers()
        prewarmLLMIfEnabled()

        // Register Cmd+Ctrl+V to paste the last history entry
        historyHotkeyManager.register { [weak self] in
            Task { @MainActor in
                await self?.pasteLastFromHistory()
            }
        }
    }

    private func installOverlayObservers() {
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
                if appState.isRecording {
                    await self.confirm()
                } else if appState.isPreviewing {
                    await self.pasteFromPreview()
                }
            }
        }
    }

    /// Pre-download the speech model for the user's selected locale so it's
    /// ready when they start recording.
    func preloadModel() {
        let locale = UserDefaults.standard.string(forKey: "locale")
            .flatMap { Locale(identifier: $0) } ?? Locale.current
        let localeID = locale.identifier(.bcp47)

        // Reuse an existing task if one is already preloading this locale
        if let existing = preloadTasksByLocale[localeID], !existing.isCancelled {
            return
        }

        // Cancel any in-flight preloads for other locales — they are no longer needed
        for (_, task) in preloadTasksByLocale {
            task.cancel()
        }
        preloadTasksByLocale.removeAll()

        let task = Task { [weak self, modelManager] in
            do {
                try await modelManager.ensureModelAvailable(for: locale)
            } catch is CancellationError {
                return
            } catch {}

            guard let self else { return }
            // Only clear if this is still the active task for this locale
            if self.preloadTasksByLocale[localeID] != nil {
                self.preloadTasksByLocale.removeValue(forKey: localeID)
            }
        }
        preloadTasksByLocale[localeID] = task
    }

    /// Start a dictation session.
    func start() async {
        guard let appState, !appState.isRecording, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        let locale = UserDefaults.standard.string(forKey: "locale")
            .flatMap { Locale(identifier: $0) } ?? Locale.current
        let localeID = locale.identifier(.bcp47)

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

        // Reset state and show overlay immediately so the user gets feedback
        appState.reset()
        overlayManager.show(appState: appState)

        // Wait for the matching preload to finish before starting audio to avoid duplicate downloads.
        await awaitPreload(for: localeID)

        // Re-check after the suspension window — another start() may have run while we were waiting
        guard !appState.isRecording else { return }

        // Cancel all preloads so they don't consume bandwidth during recording
        for (_, task) in preloadTasksByLocale {
            task.cancel()
        }
        preloadTasksByLocale.removeAll()

        // Set up audio level monitor for waveform visualization
        let monitor = AudioLevelMonitor()
        audioLevelMonitor = monitor
        transcriptionEngine.levelMonitor = monitor
        appState.audioLevel = monitor

        transcriptionEngine.selectedDeviceID = audioDeviceManager?.resolvedDeviceID

        do {
            try await transcriptionEngine.startSession(appState: appState, locale: locale)
        } catch {
            handleStartError(error, appState: appState)
            return
        }

        SoundFeedback.playStartSound()
        installRecordingKeyMonitor()
        prewarmLLMIfEnabled()
    }

    /// Confirm and paste the transcribed text.
    func confirm() async {
        guard let appState, appState.isRecording else { return }

        // Capture setting before async work so it reflects the user's
        // intent at the time they stopped recording.
        let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")

        let text = await stopAndProcess()

        // Paste if we have text
        if !text.isEmpty {
            await deliverText(text, autoPaste: autoPaste)
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
}

// MARK: - Preview & History

extension AppCoordinator {
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

        let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
        let text = appState.previewText
        removePreviewMonitors()

        // Paste if we have text
        if !text.isEmpty {
            appState.reset()
            await deliverText(text, autoPaste: autoPaste)
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
            showPasteFailedHint(text: entry.processedText)
        }
    }
}

// MARK: - Private Helpers

extension AppCoordinator {
    private func handleStartError(_ error: Error, appState: AppState) {
        appState.error = error.localizedDescription
        appState.isRecording = false
        overlayManager.hide()
        audioLevelMonitor = nil
        appState.audioLevel = nil
        transcriptionEngine.levelMonitor = nil
    }

    private func prewarmLLMIfEnabled() {
        if UserDefaults.standard.bool(forKey: "llmRewrite") {
            Task {
                await LLMRewriter.prewarm()
            }
        }
    }

    /// Stop transcription, run post-processing, and save to history.
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

    /// Race the in-flight preload for `localeID` against a 10-second timeout.
    private func awaitPreload(for localeID: String) async {
        guard let matchingTask = preloadTasksByLocale[localeID] else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskCancellationHandler {
                    await matchingTask.value
                } onCancel: {
                    matchingTask.cancel()
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000) // 10s grace period
            }
            _ = await group.next()
            group.cancelAll()
        }
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

    /// Deliver transcribed text via auto-paste or clipboard copy.
    private func deliverText(_ text: String, autoPaste: Bool) async {
        overlayManager.hide()

        if autoPaste {
            let success = await pasteService.paste(text, into: previousApp)
            if !success {
                showPasteFailedHint(text: text)
            }
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            previousApp?.activate()
        }
    }

    /// Show the paste-failed hint overlay and schedule auto-dismiss.
    /// Copies `text` to the clipboard so the user can manually paste.
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Dismiss the paste-failed hint if it's still showing.
    private func dismissPasteFailedHint() {
        guard let appState, appState.pasteFailedHint else { return }
        pasteFailedHintTimer?.cancel()
        pasteFailedHintTimer = nil
        overlayManager.hide()
        appState.pasteFailedHint = false
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
