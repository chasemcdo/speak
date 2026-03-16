import AppKit
import CoreAudio
@testable import Speak
import Testing

// MARK: - Mocks

@MainActor
private final class MockTranscriber: Transcribing {
    var levelMonitor: AudioLevelMonitor?
    var selectedDeviceID: AudioDeviceID?
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
    var pasteResult = true
    var pasteAndSubmitCalled = false
    var pasteAndSubmitText: String?
    var pasteAndSubmitResult = true

    @discardableResult
    func paste(_ text: String, into app: NSRunningApplication?) async -> Bool {
        pasteCalled = true
        pastedText = text
        return pasteResult
    }

    @discardableResult
    func pasteAndSubmit(_ text: String, into app: NSRunningApplication?) async -> Bool {
        pasteAndSubmitCalled = true
        pasteAndSubmitText = text
        return pasteAndSubmitResult
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

    func hasFocusedTextField(in app: NSRunningApplication?) -> Bool {
        true
    }
}

private final class MockHotkey: HotkeyManaging {
    var isConversationMode = false
    var onModeChange: ((RecordingMode) -> Void)?

    func register(
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onModeChange: @escaping (RecordingMode) -> Void,
        onConversationToggle: @escaping () -> Void
    ) {
        self.onModeChange = onModeChange
    }

    func resetState() {}
}

private final class MockHistoryHotkey: HistoryHotkeyManaging {
    func register(onPasteLast: @escaping () -> Void) {}
}

// MARK: - Helpers

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

// MARK: - Tests

@Suite(.serialized)
struct PipelineIntegrationTests {
    @Test @MainActor
    func `full dictation flow`() async {
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
    func `cancel flow resets state`() async {
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
    func `mic permission denied sets error`() async {
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
    func `speech permission denied sets error`() async {
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
    func `empty transcription skips paste`() async {
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
    func `transcription error dismisses overlay`() async {
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
}

@Suite(.serialized)
struct PipelineMonitorTests {
    // MARK: - Audio level monitor wiring

    @Test @MainActor
    func `start wires audio level monitor`() async {
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
    func `confirm clears audio level monitor`() async {
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
    func `cancel clears audio level monitor`() async {
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

    // MARK: - Recording mode wiring

    @Test @MainActor
    func `mode change wires to app state`() async {
        configureDefaults()

        let hotkey = MockHotkey()
        let transcriber = MockTranscriber()
        let overlay = MockOverlay()
        let paster = MockPaster()
        let appState = AppState()
        let historyStore = HistoryStore()

        let coordinator = makeCoordinator(
            transcriber: transcriber, overlay: overlay, paster: paster,
            hotkeyManager: hotkey
        )
        coordinator.setUp(appState: appState, historyStore: historyStore)

        hotkey.onModeChange?(.hold)
        await Task.yield()
        #expect(appState.recordingMode == .hold)

        hotkey.onModeChange?(.toggle)
        await Task.yield()
        #expect(appState.recordingMode == .toggle)
    }

    @Test @MainActor
    func `confirm from overlay during recording stops and pastes`() async {
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
        appState.appendFinalizedText("Stop button text.")

        NotificationCenter.default.post(name: .overlayConfirmRequested, object: nil)
        // Yield until the notification handler's async Task completes
        for _ in 0 ..< 100 {
            await Task.yield()
            if paster.pasteCalled { break }
        }

        #expect(transcriber.stopSessionCalled)
        #expect(paster.pasteCalled)
        #expect(paster.pastedText == "Stop button text.")
        #expect(overlay.hideCalled)
    }

    @Test @MainActor
    func `confirm from overlay when not recording is no op`() async {
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

        // Don't start recording — post confirm notification
        NotificationCenter.default.post(name: .overlayConfirmRequested, object: nil)
        await Task.yield()

        #expect(!paster.pasteCalled)
        #expect(!transcriber.stopSessionCalled)
    }

    @Test @MainActor
    func `mode resets on next start`() async {
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
        appState.recordingMode = .toggle
        appState.appendFinalizedText("Text")

        await coordinator.confirm()
        #expect(appState.recordingMode == .toggle)

        // start() calls reset() which clears recordingMode
        await coordinator.start()
        #expect(appState.recordingMode == .hold)
    }

    @Test @MainActor
    func `mode resets after cancel`() async {
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
        appState.recordingMode = .toggle

        await coordinator.cancel()

        #expect(appState.recordingMode == .hold)
    }

    @Test @MainActor
    func `transcription error clears audio level monitor`() async {
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
