import AppKit
import Observation

/// Orchestrates the full dictation flow: hotkey → overlay → transcribe → post-process → paste.
@MainActor
@Observable
final class AppCoordinator {
    private let transcriptionEngine = TranscriptionEngine()
    private let overlayManager = OverlayManager()
    private let hotkeyManager = HotkeyManager()
    private let textProcessor = TextProcessor()
    private let contextReader = ContextReader()

    private var previousApp: NSRunningApplication?
    private var capturedContext: String?
    private var capturedVocabulary: ScreenVocabulary?
    private var appState: AppState?

    /// Set up the coordinator with the shared app state. Call once at app launch.
    func setUp(appState: AppState) {
        self.appState = appState

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
                await self?.cancel()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .overlayConfirmRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.confirm()
            }
        }

        // Prewarm the LLM if the user has it enabled
        if UserDefaults.standard.bool(forKey: "llmRewrite") {
            Task {
                await LLMRewriter.prewarm()
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

        var text = appState.displayText

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

    // MARK: - Private

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
