import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio
import Speech

final class AudioCaptureManager: @unchecked Sendable {
    private var audioUnit: AudioUnit?
    private let callbackState = InputCallbackState()
    private let captureQueue = DispatchQueue(label: "com.speak.audio-capture", qos: .userInteractive)

    deinit {
        stopCapture()
    }

    var levelMonitor: AudioLevelMonitor? {
        get { callbackState.levelMonitor }
        set { callbackState.levelMonitor = newValue }
    }

    var isCapturing: Bool {
        audioUnit != nil
    }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var permissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var permissionNotDetermined: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    // MARK: - Input validation

    /// Validate that an audio input device is available.
    private func validateAudioInput() throws {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw AudioCaptureError.noAudioInputDevice
        }
    }

    // MARK: - Format negotiation

    /// Determine the best audio format compatible with the given transcriber module.
    /// Call this before startCapture to set up format conversion.
    func prepareFormat(compatibleWith module: SpeechTranscriber) async throws {
        try validateAudioInput()
        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module]
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }
        callbackState.targetFormat = bestFormat
    }

    // MARK: - Capture

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard audioUnit == nil else {
            throw AudioCaptureError.alreadyCapturing
        }
        guard Self.permissionGranted else {
            throw AudioCaptureError.microphonePermissionDenied
        }
        try validateAudioInput()

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        callbackState.continuation = continuation
        callbackState.converter = nil

        let deviceID = try Self.preferredInputDeviceID()

        // Use a HAL Output audio unit for raw hardware access.
        // Unlike AVAudioEngine (VoiceProcessingIO) or AVCaptureSession, the HAL
        // Output unit does not engage the communication audio path, so macOS will
        // not duck other audio while the microphone is active.
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioCaptureError.noAudioInputDevice
        }

        var unit: AudioUnit?
        try osCheck(AudioComponentInstanceNew(component, &unit))
        guard let unit else { throw AudioCaptureError.noAudioInputDevice }

        do {
            // Enable input on element 1 (mic side).
            var enableIO: UInt32 = 1
            try osCheck(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input, 1,
                &enableIO, UInt32(MemoryLayout<UInt32>.size)
            ))

            // Disable output on element 0 (speaker side).
            var disableIO: UInt32 = 0
            try osCheck(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output, 0,
                &disableIO, UInt32(MemoryLayout<UInt32>.size)
            ))

            // Point the unit at the default input device.
            var devID = deviceID
            try osCheck(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0,
                &devID, UInt32(MemoryLayout<AudioDeviceID>.size)
            ))

            // Query the hardware's native format so we can request Float32 at the
            // same sample rate / channel count.
            var hwFormat = AudioStreamBasicDescription()
            var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try osCheck(AudioUnitGetProperty(
                unit, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input, 1,
                &hwFormat, &fmtSize
            ))

            // Ask the AU's internal converter to deliver Float32 non-interleaved
            // PCM on element 1's output scope (what our callback receives).
            var captureASBD = AudioStreamBasicDescription(
                mSampleRate: hwFormat.mSampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved
                    | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: hwFormat.mChannelsPerFrame,
                mBitsPerChannel: 32,
                mReserved: 0
            )
            try osCheck(AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output, 1,
                &captureASBD, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ))

            callbackState.captureFormat = AVAudioFormat(streamDescription: &captureASBD)
            callbackState.audioUnit = unit
            callbackState.captureQueue = captureQueue

            // Install the render callback on the input scope.
            var cb = AURenderCallbackStruct(
                inputProc: halInputCallback,
                inputProcRefCon: Unmanaged.passUnretained(callbackState).toOpaque()
            )
            try osCheck(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global, 0,
                &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ))

            try osCheck(AudioUnitInitialize(unit))
            try osCheck(AudioOutputUnitStart(unit))
        } catch {
            callbackState.audioUnit = nil
            callbackState.captureFormat = nil
            callbackState.continuation?.finish()
            callbackState.continuation = nil
            callbackState.converter = nil
            AudioComponentInstanceDispose(unit)
            throw error
        }

        audioUnit = unit
        return stream
    }

    func stopCapture() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }
        callbackState.audioUnit = nil
        callbackState.continuation?.finish()
        callbackState.continuation = nil
        callbackState.converter = nil
    }

    // MARK: - Helpers

    // MARK: - Device selection

    /// Choose the best input device for capture. When the system default input
    /// is Bluetooth (e.g. AirPods), prefer the built-in microphone instead.
    /// Bluetooth audio can only carry high-quality output (A2DP) OR bidirectional
    /// headset audio (HFP) — not both. Using the Bluetooth mic forces a codec
    /// switch that degrades playback quality in the user's headphones.
    private static func preferredInputDeviceID() throws -> AudioDeviceID {
        let defaultID = try getDeviceID(for: kAudioHardwarePropertyDefaultInputDevice)

        guard isBluetooth(defaultID),
              let builtInID = findBuiltInInputDevice()
        else { return defaultID }

        return builtInID
    }

    private static func getDeviceID(
        for selector: AudioObjectPropertySelector
    ) throws -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { throw AudioCaptureError.noAudioInputDevice }
        return deviceID
    }

    private static func isBluetooth(_ deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType) == noErr
        else { return false }

        return transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func findBuiltInInputDevice() -> AudioDeviceID? {
        var propSize: UInt32 = 0
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr, 0, nil, &propSize
        ) == noErr else { return nil }

        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr, 0, nil, &propSize, &devices
        ) == noErr else { return nil }

        for deviceID in devices {
            // Must be built-in transport.
            var transport: UInt32 = 0
            var tSize = UInt32(MemoryLayout<UInt32>.size)
            var tAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(deviceID, &tAddr, 0, nil, &tSize, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBuiltIn
            else { continue }

            // Must have input streams.
            var streamsSize: UInt32 = 0
            var streamsAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nil, &streamsSize) == noErr,
                  streamsSize > 0
            else { continue }

            return deviceID
        }
        return nil
    }

    private func osCheck(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioCaptureError.invalidAudioFormat }
    }
}

// MARK: - HAL Input Callback

/// Free function suitable for use as an `AURenderCallbackStruct.inputProc`.
/// Renders captured audio into a PCM buffer and dispatches it off the real-time
/// I/O thread for level monitoring and format conversion.
private func halInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let state = Unmanaged<InputCallbackState>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let audioUnit = state.audioUnit,
          let captureFormat = state.captureFormat
    else { return noErr }

    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: inNumberFrames)
    else { return noErr }
    pcmBuffer.frameLength = inNumberFrames

    let status = AudioUnitRender(
        audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames,
        pcmBuffer.mutableAudioBufferList
    )
    guard status == noErr else { return status }

    // Dispatch off the real-time I/O thread for processing.
    state.captureQueue?.async {
        state.processBuffer(pcmBuffer)
    }
    return noErr
}

// MARK: - InputCallbackState

/// Shared mutable state accessed from the HAL I/O callback and the processing queue.
/// All property access is serialized through `lock` to prevent data races between
/// the caller thread (start/stop), the I/O callback, and the processing queue.
private final class InputCallbackState: @unchecked Sendable {
    private let lock = NSLock()

    private var _continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var _converter: AVAudioConverter?
    private var _targetFormat: AVAudioFormat?
    private var _captureFormat: AVAudioFormat?
    private var _levelMonitor: AudioLevelMonitor?
    private var _audioUnit: AudioUnit?
    private var _captureQueue: DispatchQueue?

    var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation? {
        get { lock.withLock { _continuation } }
        set { lock.withLock { _continuation = newValue } }
    }

    var converter: AVAudioConverter? {
        get { lock.withLock { _converter } }
        set { lock.withLock { _converter = newValue } }
    }

    var targetFormat: AVAudioFormat? {
        get { lock.withLock { _targetFormat } }
        set { lock.withLock { _targetFormat = newValue } }
    }

    var captureFormat: AVAudioFormat? {
        get { lock.withLock { _captureFormat } }
        set { lock.withLock { _captureFormat = newValue } }
    }

    var levelMonitor: AudioLevelMonitor? {
        get { lock.withLock { _levelMonitor } }
        set { lock.withLock { _levelMonitor = newValue } }
    }

    var audioUnit: AudioUnit? {
        get { lock.withLock { _audioUnit } }
        set { lock.withLock { _audioUnit = newValue } }
    }

    var captureQueue: DispatchQueue? {
        get { lock.withLock { _captureQueue } }
        set { lock.withLock { _captureQueue = newValue } }
    }

    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        levelMonitor?.updateRMS(from: buffer)

        guard let targetFormat else {
            continuation?.yield(buffer)
            return
        }

        // Lazily create converter on first buffer when the capture format is known.
        if converter == nil {
            if buffer.format.sampleRate == targetFormat.sampleRate,
               buffer.format.channelCount == targetFormat.channelCount,
               buffer.format.commonFormat == targetFormat.commonFormat {
                continuation?.yield(buffer)
                return
            }
            guard let conv = AVAudioConverter(from: buffer.format, to: targetFormat) else { return }
            converter = conv
        }

        guard let converter,
              let converted = Self.convertBuffer(buffer, using: converter, to: targetFormat)
        else { return }
        continuation?.yield(converted)
    }

    static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (format.sampleRate / buffer.format.sampleRate)
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }

        let state = ConversionState(buffer: buffer)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if state.didProvideData {
                outStatus.pointee = .noDataNow
                return nil
            }
            state.didProvideData = true
            outStatus.pointee = .haveData
            return state.buffer
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if error != nil || status == .error {
            return nil
        }
        return outputBuffer
    }
}

// MARK: - ConversionState

/// Reference type to safely pass mutable state into @Sendable converter closure.
private final class ConversionState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideData = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case alreadyCapturing
    case formatConversionFailed
    case microphonePermissionDenied
    case noAudioInputDevice
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "Audio capture is already running."
        case .formatConversionFailed:
            return "Failed to convert audio format for speech recognition."
        case .microphonePermissionDenied:
            return "Microphone access is required for dictation."
        case .noAudioInputDevice:
            return "No microphone found. Please connect an audio input device."
        case .invalidAudioFormat:
            return "Audio input device has an invalid format."
        }
    }
}
