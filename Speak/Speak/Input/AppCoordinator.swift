import AppKit
import Observation

/// Orchestrates the full dictation flow: hotkey → overlay → transcribe → paste.
@MainActor
@Observable
final class AppCoordinator {
    private let transcriptionEngine = TranscriptionEngine()
    private let overlayManager = OverlayManager()
    private let hotkeyManager = HotkeyManager()

    private var previousApp: NSRunningApplication?
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
    }

    /// Confirm and paste the transcribed text.
    func confirm() async {
        guard let appState, appState.isRecording else { return }

        // Reset hotkey state in case recording was stopped via keyboard/menu
        hotkeyManager.resetState()

        // Stop transcription
        await transcriptionEngine.stopSession()
        appState.isRecording = false

        let text = appState.displayText

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
    }
}
