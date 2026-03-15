import CoreAudio
@testable import Speak
import Testing

struct AudioDeviceManagerTests {
    @Test @MainActor
    func `enumeration returns valid devices`() {
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
    func `selected device UID persists through UserDefaults`() {
        let defaults = UserDefaults.standard
        // Clean up before test
        defaults.removeObject(forKey: "selectedInputDeviceUID")

        let manager = AudioDeviceManager()
        #expect(manager.selectedDeviceUID == nil)

        guard let firstDevice = manager.inputDevices.first else {
            return // Skip if no devices (unlikely)
        }

        manager.selectedDeviceUID = firstDevice.uid
        #expect(defaults.string(forKey: "selectedInputDeviceUID") == firstDevice.uid)

        // A new manager instance should load the persisted UID
        let manager2 = AudioDeviceManager()
        #expect(manager2.selectedDeviceUID == firstDevice.uid)

        // Clean up
        defaults.removeObject(forKey: "selectedInputDeviceUID")
    }

    @Test @MainActor
    func `disconnected device UID resolves to nil`() {
        let defaults = UserDefaults.standard
        defaults.set("nonexistent-device-uid-12345", forKey: "selectedInputDeviceUID")

        let manager = AudioDeviceManager()
        // The manager should have cleared the UID since the device isn't connected
        #expect(manager.selectedDeviceUID == nil)
        #expect(manager.resolvedDeviceID == nil)

        // Clean up
        defaults.removeObject(forKey: "selectedInputDeviceUID")
    }

    @Test @MainActor
    func `system default selection resolves to nil`() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "selectedInputDeviceUID")

        let manager = AudioDeviceManager()
        #expect(manager.selectedDeviceUID == nil)
        #expect(manager.resolvedDeviceID == nil)

        // Clean up
        defaults.removeObject(forKey: "selectedInputDeviceUID")
    }

    @Test @MainActor
    func `valid device UID resolves to device ID`() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "selectedInputDeviceUID")

        let manager = AudioDeviceManager()
        guard let firstDevice = manager.inputDevices.first else {
            return // Skip if no devices
        }

        manager.selectedDeviceUID = firstDevice.uid
        #expect(manager.resolvedDeviceID == firstDevice.id)

        // Clean up
        defaults.removeObject(forKey: "selectedInputDeviceUID")
    }
}
