import AppKit
import Observation

/// Orchestrates the full dictation flow: hotkey → overlay → transcribe → post-process → paste.
@MainActor
@Observable
final class AppCoordinator {
    private let transcriptionEngine = TranscriptionEngine()
    private let overlayManager = OverlayManager()
    private let hotkeyManager = HotkeyManager()
    private let historyHotkeyManager = HistoryHotkeyManager()
    private let textProcessor = TextProcessor()
    private let contextReader = ContextReader()

    private var previousApp: NSRunningApplication?
    private var capturedContext: String?
    private var capturedVocabulary: ScreenVocabulary?
    private var appState: AppState?
    private var historyStore: HistoryStore?
    private var previewDismissTimer: DispatchWorkItem?
    private var previewKeyMonitor: Any?

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
        NotificationCenter.default.addObserver(
            forName: .overlayCancelRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let appState = self.appState else { return }
                if appState.isDismissedPreview {
                    self.dismissPreview()
                } else if appState.isRecording {
                    await self.stopWithoutPaste()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .overlayConfirmRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let appState = self.appState else { return }
                if appState.isDismissedPreview {
                    await self.pasteFromPreview()
                } else if appState.isRecording {
                    await self.confirm()
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
        if appState.isDismissedPreview {
            dismissPreview()
        }

        // Pre-check permissions before showing the overlay
        guard AudioCaptureManager.permissionGranted else {
            appState.error = AudioCaptureError.microphonePermissionDenied.localizedDescription
            return
        }
        guard ModelManager.authorizationGranted else {
            appState.error = TranscriptionError.notAuthorized.localizedDescription
            return
        }

        // Remember which app had focus
        previousApp = NSWorkspace.shared.frontmostApplication

        // Capture context from the focused text field before we steal focus
        capturedContext = contextReader.readContext(from: previousApp)

        // Capture screen vocabulary (names, filenames, terms) if enabled
        if UserDefaults.standard.bool(forKey: "screenContext") {
            capturedVocabulary = contextReader.readScreenVocabulary(from: previousApp)
        }

        // Reset state
        appState.reset()

        // Show the overlay
        overlayManager.show(appState: appState)

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
            previousApp?.activate()
            previousApp = nil
            capturedContext = nil
            capturedVocabulary = nil
            return
        }

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

        // Reset hotkey state in case recording was stopped via keyboard/menu
        hotkeyManager.resetState()

        // Stop transcription
        await transcriptionEngine.stopSession()
        appState.isRecording = false

        let rawText = appState.displayText
        var text = rawText

        // Run post-processing pipeline if we have text
        if !text.isEmpty {
            // Build the filter pipeline based on user preferences
            configureFilters()

            if !textProcessor.filters.isEmpty {
                appState.isPostProcessing = true

                let locale = UserDefaults.standard.string(forKey: "locale")
                    .flatMap { Locale(identifier: $0) } ?? Locale.current

                let context = ProcessingContext(
                    surroundingText: capturedContext,
                    screenVocabulary: capturedVocabulary,
                    locale: locale
                )

                text = await textProcessor.process(text, context: context)
                appState.isPostProcessing = false
            }
        }

        // Save to history
        if !text.isEmpty {
            historyStore?.add(HistoryEntry(
                rawText: rawText,
                processedText: text,
                sourceAppName: previousApp?.localizedName,
                sourceAppBundleID: previousApp?.bundleIdentifier
            ))
        }

        // Hide overlay
        overlayManager.hide()

        // Paste if we have text
        if !text.isEmpty {
            let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
            if autoPaste {
                await PasteService.paste(text, into: previousApp)
            } else {
                // Just leave it on the clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                // Re-activate the previous app
                previousApp?.activate()
            }
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

        await transcriptionEngine.stopSession()
        appState.reset()
        overlayManager.hide()

        // Re-activate the previous app
        previousApp?.activate()
        previousApp = nil
        capturedContext = nil
        capturedVocabulary = nil
    }

    /// Stop recording and show a preview without pasting.
    func stopWithoutPaste() async {
        guard let appState, appState.isRecording else { return }

        // Reset hotkey state
        hotkeyManager.resetState()

        // Stop transcription
        await transcriptionEngine.stopSession()
        appState.isRecording = false

        let rawText = appState.displayText
        var text = rawText

        // Run post-processing pipeline if we have text
        if !text.isEmpty {
            configureFilters()

            if !textProcessor.filters.isEmpty {
                appState.isPostProcessing = true

                let locale = UserDefaults.standard.string(forKey: "locale")
                    .flatMap { Locale(identifier: $0) } ?? Locale.current

                let context = ProcessingContext(
                    surroundingText: capturedContext,
                    screenVocabulary: capturedVocabulary,
                    locale: locale
                )

                text = await textProcessor.process(text, context: context)
                appState.isPostProcessing = false
            }
        }

        // Save to history
        if !text.isEmpty {
            historyStore?.add(HistoryEntry(
                rawText: rawText,
                processedText: text,
                sourceAppName: previousApp?.localizedName,
                sourceAppBundleID: previousApp?.bundleIdentifier
            ))
        }

        // Enter preview state — overlay stays visible
        appState.isDismissedPreview = true
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
        guard let appState, appState.isDismissedPreview else { return }

        let text = appState.previewText
        removePreviewMonitors()

        // Hide overlay and reset state
        overlayManager.hide()
        appState.reset()

        // Paste if we have text
        if !text.isEmpty {
            let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
            if autoPaste {
                await PasteService.paste(text, into: previousApp)
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                previousApp?.activate()
            }
        }

        previousApp = nil
        capturedContext = nil
        capturedVocabulary = nil
    }

    /// Dismiss the preview without pasting.
    func dismissPreview() {
        guard let appState else { return }

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
        await PasteService.paste(entry.processedText, into: currentApp)
    }

    // MARK: - Private

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
