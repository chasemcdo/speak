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
    var showCallCount = 0
    var hideCalled = false
    var hideCallCount = 0

    func show(appState: AppState) {
        showCalled = true
        showCallCount += 1
    }

    func hide() {
        hideCalled = true
        hideCallCount += 1
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
    var readContextCallCount = 0
    var readScreenVocabularyCallCount = 0
    var hasFocusedTextFieldResult = true

    func readContext(from app: NSRunningApplication?) -> String? {
        readContextCallCount += 1
        return nil
    }

    func readScreenVocabulary(from app: NSRunningApplication?) -> ScreenVocabulary? {
        readScreenVocabularyCallCount += 1
        return nil
    }

    func hasFocusedTextField(in app: NSRunningApplication?) -> Bool {
        hasFocusedTextFieldResult
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

    // MARK: - Context capture timing

    @Test @MainActor
    func contextNotReadAtStart() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()

        // Context should NOT be read at start time
        #expect(context.readContextCallCount == 0)
    }

    @Test @MainActor
    func contextReadAtConfirmTime() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        // Context should be read once during stopAndProcess
        #expect(context.readContextCallCount == 1)
    }

    @Test @MainActor
    func contextReadAtPreviewTime() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()

        // Context should be read once during stopAndProcess
        #expect(context.readContextCallCount == 1)
    }

    // MARK: - Paste-fail behavior

    @Test @MainActor
    func confirmWithNoTextFieldSkipsPasteAndShowsHint() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(!paster.pasteCalled)
        #expect(appState.pasteFailedHint)
    }

    @Test @MainActor
    func confirmWithNoTextFieldPutsTextOnClipboard() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        let clipboardText = NSPasteboard.general.string(forType: .string)
        #expect(clipboardText == "Hello world")
    }

    @Test @MainActor
    func confirmWithTextFieldStillPastesNormally() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = true
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(paster.pasteCalled)
        #expect(!appState.pasteFailedHint)
    }

    @Test @MainActor
    func pasteFromPreviewWithNoTextFieldShowsHint() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()

        await coordinator.pasteFromPreview()

        #expect(!paster.pasteCalled)
        #expect(appState.pasteFailedHint)
    }

    // MARK: - Screen vocabulary capture timing

    @Test @MainActor
    func screenVocabularyNotReadAtStart() async {
        configureDefaults()
        UserDefaults.standard.set(true, forKey: "screenContext")

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()

        #expect(context.readScreenVocabularyCallCount == 0)
    }

    @Test @MainActor
    func screenVocabularyReadAtStopTime() async {
        configureDefaults()
        UserDefaults.standard.set(true, forKey: "screenContext")

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(context.readScreenVocabularyCallCount == 1)
    }

    // MARK: - Paste-fail overlay behavior

    @Test @MainActor
    func confirmWithNoTextFieldShowsOverlay() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")

        // show called once for start(), should be called again for hint
        #expect(overlay.showCallCount == 1)

        await coordinator.confirm()

        #expect(overlay.showCallCount == 2)
        // Overlay should NOT be hidden — it's showing the hint
        #expect(overlay.hideCallCount == 0)
    }

    @Test @MainActor
    func confirmWithNoTextFieldStillSavesToHistory() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        // Text should still be in history even though paste failed
        #expect(historyStore.mostRecent?.processedText == "Hello world")
    }

    @Test @MainActor
    func pasteFromPreviewWithNoTextFieldPutsTextOnClipboard() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Preview text")
        await coordinator.stopWithoutPaste()

        await coordinator.pasteFromPreview()

        let clipboardText = NSPasteboard.general.string(forType: .string)
        #expect(clipboardText == "Preview text")
    }

    @Test @MainActor
    func pasteFromPreviewWithNoTextFieldClearsPreviewState() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()
        #expect(appState.isPreviewing)

        await coordinator.pasteFromPreview()

        // Preview state should be cleared, paste-failed hint should be active
        #expect(!appState.isPreviewing)
        #expect(appState.pasteFailedHint)
    }

    // MARK: - Dismiss paste-failed hint

    @Test @MainActor
    func dismissPasteFailedHintResetsState() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(appState.pasteFailedHint)

        // Simulate Escape via the cancel notification
        NotificationCenter.default.post(name: .overlayCancelRequested, object: nil)
        // Let the async task run
        await Task.yield()

        #expect(!appState.pasteFailedHint)
        #expect(overlay.hideCalled)
    }

    @Test @MainActor
    func newRecordingAfterPasteFailedHintWorks() async {
        configureDefaults()

        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            contextReader: context
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        // First flow: record → paste fails
        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()
        #expect(appState.pasteFailedHint)

        // Dismiss the hint
        NotificationCenter.default.post(name: .overlayCancelRequested, object: nil)
        await Task.yield()

        // Second flow: should be able to start a new recording
        context.hasFocusedTextFieldResult = true
        await coordinator.start()
        #expect(appState.isRecording)
        #expect(!appState.pasteFailedHint)
    }
}
