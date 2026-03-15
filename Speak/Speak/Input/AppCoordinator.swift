import AppKit
import Observation

/// Orchestrates the full dictation flow: hotkey → overlay → transcribe → post-process → paste.
@MainActor
@Observable
final class AppCoordinator {
    var transcriptionEngine: any Transcribing
    let overlayManager: any OverlayPresenting
    let hotkeyManager: any HotkeyManaging
    private let historyHotkeyManager: any HistoryHotkeyManaging
    let textProcessor = TextProcessor()
    let contextReader: any ContextReading
    let pasteService: any Pasting
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

    var previousApp: NSRunningApplication?
    var capturedContext: String?
    var capturedVocabulary: ScreenVocabulary?
    var appState: AppState?
    var historyStore: HistoryStore?
    var previewDismissTimer: DispatchWorkItem?
    var pasteFailedHintTimer: DispatchWorkItem?
    var recordingKeyMonitor: Any?
    var previewKeyMonitor: Any?
    var audioLevelMonitor: AudioLevelMonitor?
    private var cancelObserver: Any?
    private var confirmObserver: Any?
    var preloadTasksByLocale: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var isPreparing = false
    let modelManager = ModelManager()

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
            },
            onModeChange: { [weak self] mode in
                Task { @MainActor in
                    self?.appState?.recordingMode = mode
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
                if appState.isRecording {
                    await self.confirm()
                } else if appState.isPreviewing {
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
