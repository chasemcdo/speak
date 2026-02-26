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
    var hideCallCount = 0

    func show(appState: AppState) {
        showCalled = true
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
    func readContext(from app: NSRunningApplication?) -> String? {
        nil
    }

    func readScreenVocabulary(from app: NSRunningApplication?) -> ScreenVocabulary? {
        nil
    }
}

private final class MockHotkey: HotkeyManaging {
    var resetStateCalled = false
    var resetStateCallCount = 0

    func register(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {}

    func resetState() {
        resetStateCalled = true
        resetStateCallCount += 1
    }
}

private final class MockHistoryHotkey: HistoryHotkeyManaging {
    func register(onPasteLast: @escaping () -> Void) {}
}

// MARK: - Helpers

@Suite("Preview Flow", .serialized)
struct PreviewFlowTests {
    private func configureDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "removeFillerWords")
        defaults.set(false, forKey: "autoFormat")
        defaults.set(false, forKey: "llmRewrite")
        defaults.set(true, forKey: "autoPaste")
        defaults.set(false, forKey: "screenContext")
    }

    @MainActor
    private func makeCoordinator(
        transcriber: MockTranscriber = MockTranscriber(),
        overlay: MockOverlay = MockOverlay(),
        paster: MockPaster = MockPaster(),
        hotkeyManager: MockHotkey = MockHotkey()
    ) -> (AppCoordinator, AppState, HistoryStore, MockTranscriber, MockOverlay, MockPaster, MockHotkey) {
        let appState = AppState()
        let historyStore = HistoryStore()
        let coordinator = AppCoordinator(
            transcriptionEngine: transcriber,
            overlayManager: overlay,
            hotkeyManager: hotkeyManager,
            historyHotkeyManager: MockHistoryHotkey(),
            contextReader: MockContext(),
            pasteService: paster,
            checkMicPermission: { true },
            checkSpeechAuth: { true }
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)
        return (coordinator, appState, historyStore, transcriber, overlay, paster, hotkeyManager)
    }

    // MARK: - stopWithoutPaste

    @Test @MainActor
    func stopWithoutPasteEntersPreviewState() async {
        configureDefaults()
        let (coordinator, appState, _, transcriber, _, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")

        await coordinator.stopWithoutPaste()

        #expect(transcriber.stopSessionCalled)
        #expect(!appState.isRecording)
        #expect(appState.isPreviewing)
        #expect(appState.previewText == "Hello world")
        #expect(!paster.pasteCalled)
    }

    @Test @MainActor
    func stopWithoutPasteDoesNotHideOverlay() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, _, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        overlay.hideCalled = false // Reset after show

        await coordinator.stopWithoutPaste()

        #expect(!overlay.hideCalled)
    }

    @Test @MainActor
    func stopWithoutPasteResetsHotkeyState() async {
        configureDefaults()
        let (coordinator, appState, _, _, _, _, hotkey) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello")

        await coordinator.stopWithoutPaste()

        #expect(hotkey.resetStateCalled)
    }

    @Test @MainActor
    func stopWithoutPasteSavesToHistory() async {
        configureDefaults()
        let (coordinator, appState, historyStore, _, _, _, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")

        await coordinator.stopWithoutPaste()

        #expect(historyStore.mostRecent?.processedText == "Hello world")
    }

    @Test @MainActor
    func stopWithoutPasteWithEmptyTextSetsEmptyPreview() async {
        configureDefaults()
        let (coordinator, appState, historyStore, _, _, _, _) = makeCoordinator()
        let initialCount = historyStore.entries.count

        await coordinator.start()
        // Don't add any text

        await coordinator.stopWithoutPaste()

        #expect(appState.isPreviewing)
        #expect(appState.previewText == "")
        // Should not save empty text to history
        #expect(historyStore.entries.count == initialCount)
    }

    @Test @MainActor
    func stopWithoutPasteGuardsNotRecording() async {
        configureDefaults()
        let (coordinator, appState, _, _, _, _, _) = makeCoordinator()

        // Don't start recording — stopWithoutPaste should be a no-op
        await coordinator.stopWithoutPaste()

        #expect(!appState.isPreviewing)
    }

    // MARK: - pasteFromPreview

    @Test @MainActor
    func pasteFromPreviewPastesAndResets() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()
        overlay.hideCalled = false

        await coordinator.pasteFromPreview()

        #expect(paster.pasteCalled)
        #expect(paster.pastedText == "Hello world")
        #expect(overlay.hideCalled)
        #expect(!appState.isPreviewing)
        #expect(appState.previewText == "")
        #expect(!appState.isRecording)
    }

    @Test @MainActor
    func pasteFromPreviewWithEmptyTextSkipsPaste() async {
        configureDefaults()
        let (coordinator, appState, _, _, _, paster, _) = makeCoordinator()

        await coordinator.start()
        // Don't add text
        await coordinator.stopWithoutPaste()

        await coordinator.pasteFromPreview()

        #expect(!paster.pasteCalled)
        #expect(!appState.isPreviewing)
    }

    @Test @MainActor
    func pasteFromPreviewGuardsNotInPreview() async {
        configureDefaults()
        let (coordinator, _, _, _, _, paster, _) = makeCoordinator()

        // Not in preview state — should be a no-op
        await coordinator.pasteFromPreview()

        #expect(!paster.pasteCalled)
    }

    // MARK: - dismissPreview

    @Test @MainActor
    func dismissPreviewHidesOverlayAndResets() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()
        overlay.hideCalled = false

        coordinator.dismissPreview()

        #expect(overlay.hideCalled)
        #expect(!appState.isPreviewing)
        #expect(appState.previewText == "")
        #expect(!paster.pasteCalled)
    }

    @Test @MainActor
    func dismissPreviewIsNoOpWithoutAppState() {
        configureDefaults()
        // Coordinator without setUp — appState is nil
        let coordinator = AppCoordinator(
            transcriptionEngine: MockTranscriber(),
            overlayManager: MockOverlay(),
            hotkeyManager: MockHotkey(),
            historyHotkeyManager: MockHistoryHotkey(),
            contextReader: MockContext(),
            pasteService: MockPaster(),
            checkMicPermission: { true },
            checkSpeechAuth: { true }
        )

        // Should not crash
        coordinator.dismissPreview()
    }

    // MARK: - Full preview flow end-to-end

    @Test @MainActor
    func fullPreviewThenPasteFlow() async {
        configureDefaults()
        let (coordinator, appState, _, transcriber, overlay, paster, _) = makeCoordinator()

        // Start recording
        await coordinator.start()
        #expect(appState.isRecording)
        #expect(overlay.showCalled)

        // Simulate transcription
        appState.appendFinalizedText("The meeting is at three pm.")

        // Escape → preview (not paste)
        await coordinator.stopWithoutPaste()
        #expect(transcriber.stopSessionCalled)
        #expect(!appState.isRecording)
        #expect(appState.isPreviewing)
        #expect(appState.previewText == "The meeting is at three pm.")
        #expect(!paster.pasteCalled)

        // Return → paste from preview
        await coordinator.pasteFromPreview()
        #expect(paster.pasteCalled)
        #expect(paster.pastedText == "The meeting is at three pm.")
        #expect(!appState.isPreviewing)
    }

    @Test @MainActor
    func fullPreviewThenDismissFlow() async {
        configureDefaults()
        let (coordinator, appState, _, _, _, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Some text to review.")

        await coordinator.stopWithoutPaste()
        #expect(appState.isPreviewing)

        // Dismiss without pasting
        coordinator.dismissPreview()
        #expect(!appState.isPreviewing)
        #expect(!paster.pasteCalled)
    }

    // MARK: - start() dismisses active preview

    @Test @MainActor
    func startDismissesActivePreview() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, _, _) = makeCoordinator()

        // Enter preview state
        await coordinator.start()
        appState.appendFinalizedText("Old text")
        await coordinator.stopWithoutPaste()
        #expect(appState.isPreviewing)

        // Start a new recording — should dismiss preview first
        overlay.hideCalled = false
        await coordinator.start()

        #expect(!appState.isPreviewing)
        #expect(appState.isRecording)
    }

    // MARK: - confirm still works (no regression)

    @Test @MainActor
    func confirmStillPastesDirectly() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Direct paste text.")

        await coordinator.confirm()

        #expect(paster.pasteCalled)
        #expect(paster.pastedText == "Direct paste text.")
        #expect(overlay.hideCalled)
        #expect(!appState.isPreviewing)
        #expect(!appState.isRecording)
    }

    // MARK: - cancel still works (no regression)

    @Test @MainActor
    func cancelStillResetsWithoutPasting() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Text to cancel.")

        await coordinator.cancel()

        #expect(!paster.pasteCalled)
        #expect(overlay.hideCalled)
        #expect(!appState.isRecording)
        #expect(appState.displayText.isEmpty)
        #expect(!appState.isPreviewing)
    }

    // MARK: - Post-processing in preview

    @Test @MainActor
    func stopWithoutPasteRunsPostProcessing() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "removeFillerWords")
        defaults.set(true, forKey: "autoFormat")
        defaults.set(false, forKey: "llmRewrite")
        defaults.set(true, forKey: "autoPaste")
        defaults.set(false, forKey: "screenContext")

        let (coordinator, appState, _, _, _, _, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Um, you know, the project is basically done.")

        await coordinator.stopWithoutPaste()

        // Post-processing should have modified the text (filler removal + formatting)
        let rawInput = "Um, you know, the project is basically done."
        #expect(appState.previewText != rawInput)
        #expect(!appState.previewText.isEmpty)
        #expect(appState.isPreviewing)
    }
}
