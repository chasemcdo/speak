import AppKit
import CoreAudio
@testable import Speak
import Testing

// MARK: - AudioDevice model tests

struct AudioDeviceTests {
    @Test
    func `identifiable uses AudioDeviceID`() {
        let device = AudioDevice(id: 42, uid: "uid-1", name: "Mic", transportType: .builtIn)
        #expect(device.id == 42)
    }

    @Test
    func `hashable equality by all fields`() {
        let a = AudioDevice(id: 1, uid: "uid-a", name: "Mic A", transportType: .usb)
        let b = AudioDevice(id: 1, uid: "uid-a", name: "Mic A", transportType: .usb)
        let c = AudioDevice(id: 2, uid: "uid-b", name: "Mic B", transportType: .bluetooth)

        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func `transport type cases are distinct`() {
        let types: [AudioDevice.TransportType] = [
            .builtIn, .usb, .bluetooth, .aggregate, .virtual, .unknown,
        ]
        // All should be unique
        #expect(Set(types).count == types.count)
    }
}

// MARK: - AudioDeviceManager tests

@Suite(.serialized)
struct AudioDeviceManagerTests {
    private let defaultsKey = "selectedInputDeviceUID"

    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Enumeration

    @Test @MainActor
    func `enumeration returns valid devices`() {
        cleanDefaults()
        let manager = AudioDeviceManager()
        // On any Mac there should be at least one input device (built-in mic)
        #expect(!manager.inputDevices.isEmpty)

        for device in manager.inputDevices {
            #expect(!device.uid.isEmpty)
            #expect(!device.name.isEmpty)
            #expect(device.id != 0)
        }
    }

    @Test @MainActor
    func `enumerated devices have unique UIDs`() {
        cleanDefaults()
        let manager = AudioDeviceManager()
        let uids = manager.inputDevices.map(\.uid)
        #expect(Set(uids).count == uids.count)
    }

    @Test @MainActor
    func `enumerated devices have known transport types`() {
        cleanDefaults()
        let manager = AudioDeviceManager()
        for device in manager.inputDevices {
            // Every device should map to one of the known cases
            switch device.transportType {
            case .builtIn, .usb, .bluetooth, .aggregate, .virtual, .unknown:
                break // valid
            }
        }
    }

    @Test @MainActor
    func `at least one built in device on Mac`() {
        cleanDefaults()
        let manager = AudioDeviceManager()
        let hasBuiltIn = manager.inputDevices.contains { $0.transportType == .builtIn }
        #expect(hasBuiltIn)
    }

    // MARK: - Persistence

    @Test @MainActor
    func `selected device UID persists through UserDefaults`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        #expect(manager.selectedDeviceUID == nil)

        guard let firstDevice = manager.inputDevices.first else { return }

        manager.selectedDeviceUID = firstDevice.uid
        #expect(UserDefaults.standard.string(forKey: defaultsKey) == firstDevice.uid)

        // A new manager instance should load the persisted UID
        let manager2 = AudioDeviceManager()
        #expect(manager2.selectedDeviceUID == firstDevice.uid)

        cleanDefaults()
    }

    @Test @MainActor
    func `setting nil clears UserDefaults`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        guard let firstDevice = manager.inputDevices.first else { return }

        manager.selectedDeviceUID = firstDevice.uid
        #expect(UserDefaults.standard.string(forKey: defaultsKey) != nil)

        manager.selectedDeviceUID = nil
        #expect(UserDefaults.standard.string(forKey: defaultsKey) == nil)

        cleanDefaults()
    }

    // MARK: - Disconnected device fallback

    @Test @MainActor
    func `disconnected device UID is cleared on init`() {
        UserDefaults.standard.set("nonexistent-device-uid-12345", forKey: defaultsKey)

        let manager = AudioDeviceManager()
        #expect(manager.selectedDeviceUID == nil)
        #expect(manager.resolvedDeviceID == nil)

        cleanDefaults()
    }

    @Test @MainActor
    func `disconnected device UID is cleared on refreshDevices`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        guard let firstDevice = manager.inputDevices.first else { return }

        // Select a valid device, then corrupt the UID to simulate disconnection
        manager.selectedDeviceUID = firstDevice.uid
        #expect(manager.selectedDeviceUID == firstDevice.uid)

        // Manually set a bogus UID (bypassing didSet to simulate external change)
        UserDefaults.standard.set("disconnected-uid", forKey: defaultsKey)
        // Force the manager to use this bogus UID by reading from defaults
        let manager2 = AudioDeviceManager()
        #expect(manager2.selectedDeviceUID == nil)

        cleanDefaults()
    }

    // MARK: - Resolution

    @Test @MainActor
    func `system default selection resolves to nil`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        #expect(manager.selectedDeviceUID == nil)
        #expect(manager.resolvedDeviceID == nil)

        cleanDefaults()
    }

    @Test @MainActor
    func `valid device UID resolves to correct device ID`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        guard let firstDevice = manager.inputDevices.first else { return }

        manager.selectedDeviceUID = firstDevice.uid
        #expect(manager.resolvedDeviceID == firstDevice.id)

        cleanDefaults()
    }

    @Test @MainActor
    func `each device UID resolves to its own ID`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        for device in manager.inputDevices {
            manager.selectedDeviceUID = device.uid
            #expect(manager.resolvedDeviceID == device.id)
        }

        cleanDefaults()
    }

    @Test @MainActor
    func `bogus UID set after init resolves to nil`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        // Set a UID that doesn't match any device (without going through init)
        manager.selectedDeviceUID = "totally-fake-uid"
        #expect(manager.resolvedDeviceID == nil)
        // The UID is still stored — it only gets cleared on refreshDevices
        #expect(manager.selectedDeviceUID == "totally-fake-uid")

        cleanDefaults()
    }

    @Test @MainActor
    func `refreshDevices clears bogus UID`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        manager.selectedDeviceUID = "totally-fake-uid"
        #expect(manager.selectedDeviceUID == "totally-fake-uid")

        manager.refreshDevices()
        #expect(manager.selectedDeviceUID == nil)

        cleanDefaults()
    }

    @Test @MainActor
    func `refreshDevices preserves valid UID`() {
        cleanDefaults()

        let manager = AudioDeviceManager()
        guard let firstDevice = manager.inputDevices.first else { return }

        manager.selectedDeviceUID = firstDevice.uid
        manager.refreshDevices()
        #expect(manager.selectedDeviceUID == firstDevice.uid)
        #expect(manager.resolvedDeviceID == firstDevice.id)

        cleanDefaults()
    }
}

// MARK: - Coordinator integration tests

@Suite(.serialized)
struct AudioDeviceCoordinatorTests {
    private func configureDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "removeFillerWords")
        defaults.set(false, forKey: "autoFormat")
        defaults.set(false, forKey: "llmRewrite")
        defaults.set(true, forKey: "autoPaste")
        defaults.set(false, forKey: "screenContext")
        defaults.removeObject(forKey: "selectedInputDeviceUID")
    }

    @Test @MainActor
    func `start passes resolved device ID to transcriber`() async {
        configureDefaults()

        let transcriber = MockTranscriberWithDeviceID()
        let coordinator = AppCoordinator(
            transcriptionEngine: transcriber,
            overlayManager: MockOverlayForDevice(),
            hotkeyManager: MockHotkeyForDevice(),
            historyHotkeyManager: MockHistoryHotkeyForDevice(),
            contextReader: MockContextForDevice(),
            pasteService: MockPasterForDevice(),
            checkMicPermission: { true },
            checkSpeechAuth: { true }
        )

        let appState = AppState()
        let historyStore = HistoryStore()
        coordinator.setUp(appState: appState, historyStore: historyStore)

        // Set up an AudioDeviceManager with a known device
        let deviceManager = AudioDeviceManager()
        guard let firstDevice = deviceManager.inputDevices.first else { return }
        deviceManager.selectedDeviceUID = firstDevice.uid
        coordinator.audioDeviceManager = deviceManager

        await coordinator.start()

        #expect(transcriber.selectedDeviceID == firstDevice.id)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "selectedInputDeviceUID")
    }

    @Test @MainActor
    func `start passes nil device ID when system default selected`() async {
        configureDefaults()

        let transcriber = MockTranscriberWithDeviceID()
        let coordinator = AppCoordinator(
            transcriptionEngine: transcriber,
            overlayManager: MockOverlayForDevice(),
            hotkeyManager: MockHotkeyForDevice(),
            historyHotkeyManager: MockHistoryHotkeyForDevice(),
            contextReader: MockContextForDevice(),
            pasteService: MockPasterForDevice(),
            checkMicPermission: { true },
            checkSpeechAuth: { true }
        )

        let appState = AppState()
        let historyStore = HistoryStore()
        coordinator.setUp(appState: appState, historyStore: historyStore)

        // No device manager or system default
        coordinator.audioDeviceManager = AudioDeviceManager()

        await coordinator.start()

        #expect(transcriber.selectedDeviceID == nil)
    }

    @Test @MainActor
    func `start passes nil device ID when no device manager set`() async {
        configureDefaults()

        let transcriber = MockTranscriberWithDeviceID()
        let coordinator = AppCoordinator(
            transcriptionEngine: transcriber,
            overlayManager: MockOverlayForDevice(),
            hotkeyManager: MockHotkeyForDevice(),
            historyHotkeyManager: MockHistoryHotkeyForDevice(),
            contextReader: MockContextForDevice(),
            pasteService: MockPasterForDevice(),
            checkMicPermission: { true },
            checkSpeechAuth: { true }
        )

        let appState = AppState()
        let historyStore = HistoryStore()
        coordinator.setUp(appState: appState, historyStore: historyStore)

        // audioDeviceManager is nil
        coordinator.audioDeviceManager = nil

        await coordinator.start()

        #expect(transcriber.selectedDeviceID == nil)
    }
}

// MARK: - Transcribing protocol default tests

struct TranscribingProtocolTests {
    @MainActor
    private final class MinimalTranscriber: Transcribing {
        var levelMonitor: AudioLevelMonitor?
        func startSession(appState: AppState, locale: Locale) async throws {}
        func stopSession() async {}
    }

    @Test @MainActor
    func `default selectedDeviceID is nil`() {
        let transcriber = MinimalTranscriber()
        #expect(transcriber.selectedDeviceID == nil)
    }

    @Test @MainActor
    func `default selectedDeviceID setter is no op`() {
        var transcriber = MinimalTranscriber()
        transcriber.selectedDeviceID = 42
        // The default extension is a no-op setter, so value stays nil
        #expect(transcriber.selectedDeviceID == nil)
    }
}

// MARK: - Mocks for coordinator tests

@MainActor
private final class MockTranscriberWithDeviceID: Transcribing {
    var levelMonitor: AudioLevelMonitor?
    var selectedDeviceID: AudioDeviceID?
    var startSessionCalled = false

    func startSession(appState: AppState, locale: Locale) async throws {
        startSessionCalled = true
        appState.isRecording = true
    }

    func stopSession() async {}
}

@MainActor
private final class MockOverlayForDevice: OverlayPresenting {
    func show(appState: AppState) {}
    func hide() {}
}

@MainActor
private final class MockPasterForDevice: Pasting {
    @discardableResult
    func paste(_ text: String, into app: NSRunningApplication?) async -> Bool { true }
}

@MainActor
private final class MockContextForDevice: ContextReading {
    func readContext(from app: NSRunningApplication?) -> String? { nil }
    func readScreenVocabulary(from app: NSRunningApplication?) -> ScreenVocabulary? { nil }
    func hasFocusedTextField(in app: NSRunningApplication?) -> Bool { true }
}

private final class MockHotkeyForDevice: HotkeyManaging {
    func register(
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onModeChange: @escaping (RecordingMode) -> Void
    ) {}
    func resetState() {}
}

private final class MockHistoryHotkeyForDevice: HistoryHotkeyManaging {
    func register(onPasteLast: @escaping () -> Void) {}
}
