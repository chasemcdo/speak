import AppKit
@testable import Speak
import Testing

// MARK: - Mocks

@MainActor
private final class MockTranscriber: Transcribing {
    var levelMonitor: AudioLevelMonitor?
    var startSessionCalled = false
    var stopSessionCalled = false
    var shouldThrow = false
    var receivedCustomPhrases: [String] = []

    func startSession(appState: AppState, locale: Locale, customPhrases: [String] = []) async throws {
        startSessionCalled = true
        receivedCustomPhrases = customPhrases
        if shouldThrow {
            throw TranscriptionError.notAuthorized
        }
        appState.isRecording = true
    }

    func stopSession() async {
        stopSessionCalled = true
    }
}

@MainActor
private final class MockOverlay: OverlayPresenting {
    var showCalled = false
    var hideCalled = false

    func show(appState: AppState) {
        showCalled = true
    }

    func hide() {
        hideCalled = true
    }
}

@MainActor
private final class MockPaster: Pasting {
    var pasteCalled = false
    var pastedText: String?

    func paste(_ text: String, into app: NSRunningApplication?) async {
        pasteCalled = true
        pastedText = text
    }
}

@MainActor
private final class MockContext: ContextReading {
    func readContext(from app: NSRunningApplication?) -> String? {
        nil
    }

    func readScreenVocabulary(from app: NSRunningApplication?) -> ScreenVocabulary? {
        nil
    }
}

private final class MockHotkey: HotkeyManaging {
    func register(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {}
    func resetState() {}
}

private final class MockHistoryHotkey: HistoryHotkeyManaging {
    func register(onPasteLast: @escaping () -> Void) {}
}

// MARK: - Tests

@Suite("Pipeline Integration")
struct PipelineIntegrationTests {
    private func configureDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "removeFillerWords")
        defaults.set(true, forKey: "autoFormat")
        defaults.set(false, forKey: "llmRewrite")
        defaults.set(true, forKey: "autoPaste")
        defaults.set(false, forKey: "screenContext")
    }

    @MainActor
    private func makeCoordinator(
        transcriber: any Transcribing,
        overlay: any OverlayPresenting,
        paster: any Pasting,
        contextReader: any ContextReading = MockContext(),
        hotkeyManager: any HotkeyManaging = MockHotkey(),
        historyHotkeyManager: any HistoryHotkeyManaging = MockHistoryHotkey(),
        micPermission: Bool = true,
        speechAuth: Bool = true
    ) -> AppCoordinator {
        AppCoordinator(
            transcriptionEngine: transcriber,
            overlayManager: overlay,
            hotkeyManager: hotkeyManager,
            historyHotkeyManager: historyHotkeyManager,
            contextReader: contextReader,
            pasteService: paster,
            checkMicPermission: { micPermission },
            checkSpeechAuth: { speechAuth }
        )
    }

    @Test @MainActor
    func fullDictationFlow() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        // Start recording
        await coordinator.start()
        #expect(transcriber.startSessionCalled)
        #expect(overlay.showCalled)
        #expect(appState.isRecording)

        // Simulate transcription result
        appState.appendFinalizedText("Um, you know, the project is basically done.")

        // Confirm and paste
        await coordinator.confirm()
        #expect(transcriber.stopSessionCalled)
        #expect(overlay.hideCalled)
        #expect(paster.pasteCalled)
        #expect(paster.pastedText == "The project is done.")
    }

    @Test @MainActor
    func cancelFlowResetsState() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Some transcribed text.")

        await coordinator.cancel()
        #expect(!appState.isRecording)
        #expect(appState.displayText.isEmpty)
        #expect(!paster.pasteCalled)
        #expect(overlay.hideCalled)
    }

    @Test @MainActor
    func micPermissionDeniedSetsError() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            micPermission: false
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        #expect(appState.error != nil)
        #expect(!appState.isRecording)
        #expect(!transcriber.startSessionCalled)
    }

    @Test @MainActor
    func speechPermissionDeniedSetsError() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            speechAuth: false
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        #expect(appState.error != nil)
        #expect(!appState.isRecording)
        #expect(!transcriber.startSessionCalled)
    }

    @Test @MainActor
    func emptyTranscriptionSkipsPaste() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        // Don't add any text — confirm with empty transcription
        await coordinator.confirm()
        #expect(!paster.pasteCalled)
    }

    @Test @MainActor
    func transcriptionErrorDismissesOverlay() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        transcriber.shouldThrow = true
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        #expect(overlay.hideCalled)
        #expect(appState.error != nil)
        #expect(!appState.isRecording)
    }

    // MARK: - Dictionary phrases

    @Test @MainActor
    func dictionaryPhrasesPassedToTranscriber() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()
        let dictionaryStore = DictionaryStore()
        dictionaryStore.add("Kubernetes")
        dictionaryStore.add("gRPC")

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore, dictionaryStore: dictionaryStore)

        await coordinator.start()

        #expect(transcriber.receivedCustomPhrases.contains("Kubernetes"))
        #expect(transcriber.receivedCustomPhrases.contains("gRPC"))
    }

    @Test @MainActor
    func emptyDictionaryPassesEmptyPhrases() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()
        let dictionaryStore = DictionaryStore()
        dictionaryStore.clearAll()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore, dictionaryStore: dictionaryStore)

        await coordinator.start()

        #expect(transcriber.receivedCustomPhrases.isEmpty)
    }

    @Test @MainActor
    func noDictionaryStorePassesEmptyPhrases() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        // setUp without dictionaryStore (uses default nil)
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()

        #expect(transcriber.receivedCustomPhrases.isEmpty)
    }

    // MARK: - Audio level monitor wiring

    @Test @MainActor
    func startWiresAudioLevelMonitor() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()

        // After start, both appState and transcriber should have the monitor
        #expect(appState.audioLevel != nil)
        #expect(transcriber.levelMonitor != nil)
        // They should be the same instance
        #expect(appState.audioLevel === transcriber.levelMonitor)
    }

    @Test @MainActor
    func confirmClearsAudioLevelMonitor() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        #expect(appState.audioLevel != nil)

        await coordinator.confirm()
        #expect(appState.audioLevel == nil)
        #expect(transcriber.levelMonitor == nil)
    }

    @Test @MainActor
    func cancelClearsAudioLevelMonitor() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        #expect(appState.audioLevel != nil)

        await coordinator.cancel()
        #expect(appState.audioLevel == nil)
        #expect(transcriber.levelMonitor == nil)
    }

    @Test @MainActor
    func transcriptionErrorClearsAudioLevelMonitor() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        transcriber.shouldThrow = true
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()

        // Monitor should be cleaned up after transcription error
        #expect(appState.audioLevel == nil)
        #expect(transcriber.levelMonitor == nil)
    }
}
