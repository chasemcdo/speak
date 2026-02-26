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

    func startSession(appState: AppState, locale: Locale) async throws {
        startSessionCalled = true
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
    var readContextResults: [String?] = []
    private var readContextCallCount = 0

    func readContext(from app: NSRunningApplication?) -> String? {
        guard !readContextResults.isEmpty else { return nil }
        let result = readContextResults[min(readContextCallCount, readContextResults.count - 1)]
        readContextCallCount += 1
        return result
    }

    func readScreenVocabulary(from app: NSRunningApplication?) -> ScreenVocabulary? {
        nil
    }

    func hasFocusedTextField(in app: NSRunningApplication?) -> Bool {
        true
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

    // MARK: - Dictionary replacement

    @Test @MainActor
    func dictionaryReplacementAppliedDuringPipeline() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()
        let dictionaryStore = DictionaryStore()
        dictionaryStore.add("Decoda")

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster
        )
        coordinator.setUp(appState: appState, historyStore: historyStore, dictionaryStore: dictionaryStore)

        await coordinator.start()
        appState.appendFinalizedText("I talked to Dakota about it.")

        await coordinator.confirm()

        #expect(paster.pastedText?.contains("Decoda") == true)
        #expect(paster.pastedText?.contains("Dakota") != true)
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

    // MARK: - Suggestion overlay

    @Test @MainActor
    func suggestionShownAfterEditDetection() {
        configureDefaults()
        UserDefaults.standard.set(true, forKey: "autoLearnDictionary")

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

        // Simulate edit detection directly (bypasses 3s timer)
        // Use "meting" → "meeting" which passes EditDiffer's similarity filter
        let candidates = EditDiffer.findReplacements(
            original: "the meting is at three",
            edited: "the meeting is at three"
        )
        #expect(!candidates.isEmpty)

        let suggestion = DictionarySuggestion(
            phrase: candidates[0].replacement,
            original: candidates[0].original
        )
        coordinator.handleSuggestion(suggestion)

        #expect(appState.suggestedWord != nil)
        #expect(appState.suggestedWord?.phrase == "meeting")
        #expect(overlay.showCalled)
    }

    @Test @MainActor
    func dismissSuggestionViaCancelNotification() async {
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

        // Put coordinator into suggestion state directly
        let suggestion = DictionarySuggestion(phrase: "gRPC", original: "grpc")
        coordinator.handleSuggestion(suggestion)
        #expect(appState.suggestedWord != nil)

        overlay.hideCalled = false
        // Post cancel notification
        NotificationCenter.default.post(name: .overlayCancelRequested, object: nil)
        // Allow notification delivery
        await Task.yield()

        #expect(appState.suggestedWord == nil)
        #expect(overlay.hideCalled)
    }

    @Test @MainActor
    func acceptSuggestionAddsToDictionary() async {
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

        // Put coordinator into suggestion state
        let suggestion = DictionarySuggestion(phrase: "gRPC", original: "grpc")
        coordinator.handleSuggestion(suggestion)
        #expect(appState.suggestedWord != nil)

        overlay.hideCalled = false
        // Post accept notification
        NotificationCenter.default.post(name: .overlaySuggestionAccepted, object: nil)
        await Task.yield()

        #expect(appState.suggestedWord == nil)
        #expect(overlay.hideCalled)
        #expect(dictionaryStore.entries.contains(where: { $0.phrase == "gRPC" }))
    }

    @Test @MainActor
    func startDismissesActiveSuggestion() async {
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

        // Put coordinator into suggestion state
        let suggestion = DictionarySuggestion(phrase: "gRPC", original: "grpc")
        coordinator.handleSuggestion(suggestion)
        #expect(appState.suggestedWord != nil)

        // Starting a new recording should clear the suggestion
        await coordinator.start()
        #expect(appState.suggestedWord == nil)
        #expect(appState.isRecording)
    }
}
