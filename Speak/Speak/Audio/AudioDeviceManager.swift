import CoreAudio
import os

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: TransportType

    enum TransportType: Hashable {
        case builtIn
        case usb
        case bluetooth
        case aggregate
        case virtual
        case unknown
    }
}

@MainActor
@Observable
final class AudioDeviceManager {
    private(set) var inputDevices: [AudioDevice] = []

    /// The UID of the user's selected device, or `nil` for "System Default".
    var selectedDeviceUID: String? {
        didSet {
            UserDefaults.standard.set(selectedDeviceUID, forKey: "selectedInputDeviceUID")
        }
    }

    /// Resolves the stored UID to a CoreAudio device ID.
    /// Returns `nil` when "System Default" is selected or the device is disconnected.
    var resolvedDeviceID: AudioDeviceID? {
        guard let uid = selectedDeviceUID else { return nil }
        return inputDevices.first(where: { $0.uid == uid })?.id
    }

    nonisolated private let listenerState = ListenerState()

    init() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: "selectedInputDeviceUID")
        refreshDevices()
        installListener()
    }

    deinit {
        listenerState.remove()
    }

    // MARK: - Device enumeration

    func refreshDevices() {
        inputDevices = Self.enumerateInputDevices()

        // If the selected device is no longer connected, fall back to System Default
        if let uid = selectedDeviceUID,
           !inputDevices.contains(where: { $0.uid == uid }) {
            selectedDeviceUID = nil
        }
    }

    private static func enumerateInputDevices() -> [AudioDevice] {
        var propSize: UInt32 = 0
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr, 0, nil, &propSize
        ) == noErr else { return [] }

        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr, 0, nil, &propSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            // Must have input streams
            var streamsSize: UInt32 = 0
            var streamsAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nil, &streamsSize) == noErr,
                  streamsSize > 0
            else { return nil }

            guard let uid = getStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                  let name = getStringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
            else { return nil }

            let transport = getTransportType(deviceID)
            return AudioDevice(id: deviceID, uid: uid, name: name, transportType: transport)
        }
    }

    // MARK: - Property helpers

    private static func getStringProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value) == noErr,
              let cfString = value?.takeRetainedValue()
        else { return nil }
        return cfString as String
    }

    private static func getTransportType(_ deviceID: AudioDeviceID) -> AudioDevice.TransportType {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr
        else { return .unknown }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeAggregate: return .aggregate
        case kAudioDeviceTransportTypeVirtual: return .virtual
        default: return .unknown
        }
    }

    // MARK: - Hardware change listener

    private func installListener() {
        listenerState.install { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
    }
}

// MARK: - ListenerState

/// Encapsulates the CoreAudio property listener so it can be installed/removed
/// without requiring `@MainActor`.
private final class ListenerState: @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (() -> Void)?
    private var retainedSelf: Unmanaged<ListenerState>?

    func install(onChange: @escaping () -> Void) {
        lock.withLock { self.onChange = onChange }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let ref = Unmanaged.passRetained(self)
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            listenerProc,
            ref.toOpaque()
        )
        if status == noErr {
            lock.withLock { retainedSelf = ref }
        } else {
            ref.release()
        }
    }

    func remove() {
        let ref: Unmanaged<ListenerState>? = lock.withLock {
            guard let ref = retainedSelf else { return nil }
            retainedSelf = nil
            onChange = nil
            return ref
        }
        guard ref != nil else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            listenerProc,
            ref!.toOpaque()
        )
        ref!.release()
    }

    fileprivate func fireOnChange() {
        let handler = lock.withLock { onChange }
        handler?()
    }
}

private func listenerProc(
    _: AudioObjectID,
    _: UInt32,
    _: UnsafePointer<AudioObjectPropertyAddress>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = inClientData else { return noErr }
    let state = Unmanaged<ListenerState>.fromOpaque(ptr).takeUnretainedValue()
    state.fireOnChange()
    return noErr
}
