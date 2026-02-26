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

@Suite("Paste Target")
struct PasteTargetTests {
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
        transcriber: MockTranscriber = MockTranscriber(),
        overlay: MockOverlay = MockOverlay(),
        paster: MockPaster = MockPaster(),
        context: MockContext = MockContext()
    ) -> (AppCoordinator, AppState, HistoryStore, MockTranscriber, MockOverlay, MockPaster, MockContext) {
        let appState = AppState()
        let historyStore = HistoryStore()
        let coordinator = AppCoordinator(
            transcriptionEngine: transcriber,
            overlayManager: overlay,
            hotkeyManager: MockHotkey(),
            historyHotkeyManager: MockHistoryHotkey(),
            contextReader: context,
            pasteService: paster,
            checkMicPermission: { true },
            checkSpeechAuth: { true }
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)
        return (coordinator, appState, historyStore, transcriber, overlay, paster, context)
    }

    // MARK: - Context capture timing

    @Test @MainActor
    func contextNotReadAtStart() async {
        configureDefaults()
        let (coordinator, _, _, _, _, _, context) = makeCoordinator()

        await coordinator.start()

        #expect(context.readContextCallCount == 0)
    }

    @Test @MainActor
    func contextReadAtConfirmTime() async {
        configureDefaults()
        let (coordinator, appState, _, _, _, _, context) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(context.readContextCallCount == 1)
    }

    @Test @MainActor
    func contextReadAtPreviewTime() async {
        configureDefaults()
        let (coordinator, appState, _, _, _, _, context) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()

        #expect(context.readContextCallCount == 1)
    }

    // MARK: - Screen vocabulary capture timing

    @Test @MainActor
    func screenVocabularyNotReadAtStart() async {
        configureDefaults()
        UserDefaults.standard.set(true, forKey: "screenContext")
        let (coordinator, _, _, _, _, _, context) = makeCoordinator()

        await coordinator.start()

        #expect(context.readScreenVocabularyCallCount == 0)
    }

    @Test @MainActor
    func screenVocabularyReadAtStopTime() async {
        configureDefaults()
        UserDefaults.standard.set(true, forKey: "screenContext")
        let (coordinator, appState, _, _, _, _, context) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(context.readScreenVocabularyCallCount == 1)
    }

    // MARK: - Paste-fail via confirm()

    @Test @MainActor
    func confirmWithNoTextFieldSkipsPasteAndShowsHint() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, _, paster, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(!paster.pasteCalled)
        #expect(appState.pasteFailedHint)
    }

    @Test @MainActor
    func confirmWithNoTextFieldPutsTextOnClipboard() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, _, _, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        let clipboardText = NSPasteboard.general.string(forType: .string)
        #expect(clipboardText == "Hello world")
    }

    @Test @MainActor
    func confirmWithNoTextFieldShowsOverlay() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, overlay, _, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        #expect(overlay.showCallCount == 1)

        await coordinator.confirm()

        #expect(overlay.showCallCount == 2)
        #expect(overlay.hideCallCount == 0)
    }

    @Test @MainActor
    func confirmWithNoTextFieldStillSavesToHistory() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, historyStore, _, _, _, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(historyStore.mostRecent?.processedText == "Hello world")
    }

    @Test @MainActor
    func confirmWithTextFieldStillPastesNormally() async {
        configureDefaults()
        let (coordinator, appState, _, _, _, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(paster.pasteCalled)
        #expect(!appState.pasteFailedHint)
    }

    // MARK: - Paste-fail via pasteFromPreview()

    @Test @MainActor
    func pasteFromPreviewWithNoTextFieldShowsHint() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, _, paster, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()

        await coordinator.pasteFromPreview()

        #expect(!paster.pasteCalled)
        #expect(appState.pasteFailedHint)
    }

    @Test @MainActor
    func pasteFromPreviewWithNoTextFieldPutsTextOnClipboard() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, _, _, _) = makeCoordinator(context: context)

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
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, _, _, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()
        #expect(appState.isPreviewing)

        await coordinator.pasteFromPreview()

        #expect(!appState.isPreviewing)
        #expect(appState.pasteFailedHint)
    }

    // MARK: - Dismiss paste-failed hint

    @Test @MainActor
    func dismissPasteFailedHintResetsState() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, overlay, _, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()
        #expect(appState.pasteFailedHint)

        NotificationCenter.default.post(name: .overlayCancelRequested, object: nil)
        await Task.yield()

        #expect(!appState.pasteFailedHint)
        #expect(overlay.hideCalled)
    }

    @Test @MainActor
    func newRecordingAfterPasteFailedHintWorks() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, _, _, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()
        #expect(appState.pasteFailedHint)

        NotificationCenter.default.post(name: .overlayCancelRequested, object: nil)
        await Task.yield()

        context.hasFocusedTextFieldResult = true
        await coordinator.start()
        #expect(appState.isRecording)
        #expect(!appState.pasteFailedHint)
    }
}
