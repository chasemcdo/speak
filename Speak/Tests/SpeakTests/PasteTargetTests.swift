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
    var pasteResult = true

    @discardableResult
    func paste(_ text: String, into app: NSRunningApplication?) async -> Bool {
        pasteCalled = true
        pastedText = text
        return pasteResult
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

@Suite("Paste Target", .serialized)
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

    // MARK: - Auto-paste always attempts paste regardless of text field detection

    @Test @MainActor
    func confirmAlwaysPastes() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(paster.pasteCalled)
        #expect(paster.pastedText == "Hello world")
        #expect(overlay.hideCalled)
    }

    @Test @MainActor
    func confirmSavesToHistory() async {
        configureDefaults()
        let (coordinator, appState, historyStore, _, _, _, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(historyStore.mostRecent?.processedText == "Hello world")
    }

    // MARK: - Preview paste always attempts paste

    @Test @MainActor
    func pasteFromPreviewAlwaysPastes() async {
        configureDefaults()
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()

        await coordinator.pasteFromPreview()

        #expect(paster.pasteCalled)
        #expect(paster.pastedText == "Hello world")
        #expect(!appState.isPreviewing)
        #expect(overlay.hideCalled)
    }

    // MARK: - Auto-paste OFF copies to clipboard without pasting

    @Test @MainActor
    func confirmWithAutoPasteOffCopiesToClipboard() async {
        configureDefaults()
        UserDefaults.standard.set(false, forKey: "autoPaste")
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        // Seed clipboard with a sentinel so we can verify it was overwritten
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("__sentinel__", forType: .string)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(!paster.pasteCalled)
        #expect(overlay.hideCalled)
        let clipboardText = NSPasteboard.general.string(forType: .string)
        #expect(clipboardText == "Hello world")
    }

    @Test @MainActor
    func pasteFromPreviewWithAutoPasteOffCopiesToClipboard() async {
        configureDefaults()
        UserDefaults.standard.set(false, forKey: "autoPaste")
        let (coordinator, appState, _, _, overlay, paster, _) = makeCoordinator()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("__sentinel__", forType: .string)

        await coordinator.start()
        appState.appendFinalizedText("Preview text")
        await coordinator.stopWithoutPaste()

        await coordinator.pasteFromPreview()

        #expect(!paster.pasteCalled)
        #expect(overlay.hideCalled)
        let clipboardText = NSPasteboard.general.string(forType: .string)
        #expect(clipboardText == "Preview text")
    }

    // MARK: - Paste failure shows hint

    @Test @MainActor
    func confirmShowsHintOnPasteFailure() async {
        configureDefaults()
        let paster = MockPaster()
        paster.pasteResult = false
        let (coordinator, appState, _, _, overlay, _, _) = makeCoordinator(paster: paster)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(appState.pasteFailedHint)
        #expect(overlay.showCallCount >= 2, "Overlay should be re-shown for the hint")
    }

    @Test @MainActor
    func pasteFromPreviewShowsHintOnPasteFailure() async {
        configureDefaults()
        let paster = MockPaster()
        paster.pasteResult = false
        let (coordinator, appState, _, _, overlay, _, _) = makeCoordinator(paster: paster)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.stopWithoutPaste()

        await coordinator.pasteFromPreview()

        #expect(appState.pasteFailedHint)
        #expect(overlay.showCallCount >= 2, "Overlay should be re-shown for the hint")
    }

    @Test @MainActor
    func autoPasteOffDoesNotShowHintOnFailure() async {
        configureDefaults()
        UserDefaults.standard.set(false, forKey: "autoPaste")
        let paster = MockPaster()
        paster.pasteResult = false
        let (coordinator, appState, _, _, _, _, _) = makeCoordinator(paster: paster)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(!appState.pasteFailedHint, "No hint when autoPaste is off — text is just copied to clipboard")
    }

    @Test @MainActor
    func confirmNoHintWhenNoFocusedTextField() async {
        configureDefaults()
        let context = MockContext()
        context.hasFocusedTextFieldResult = false
        let (coordinator, appState, _, _, _, paster, _) = makeCoordinator(context: context)

        await coordinator.start()
        appState.appendFinalizedText("Hello world")
        await coordinator.confirm()

        #expect(paster.pasteCalled, "Paste should still be attempted")
        #expect(!appState.pasteFailedHint, "No hint when paste succeeded — text field detection is unreliable")
    }
}
