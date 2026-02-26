@preconcurrency import AVFoundation
import Speech

/// Abstraction over the ducking configuration on an audio input node so tests can
/// verify the configuration without requiring audio hardware.
protocol AudioInputDuckingConfiguring {
    var voiceProcessingOtherAudioDuckingConfiguration: AVAudioVoiceProcessingOtherAudioDuckingConfiguration { get set }
    func setVoiceProcessingEnabled(_ enabled: Bool) throws
}

extension AVAudioInputNode: AudioInputDuckingConfiguring {}

final class AudioCaptureManager: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    var levelMonitor: AudioLevelMonitor?

    var isCapturing: Bool {
        audioEngine.isRunning
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

    /// Validate that an audio input device is available and has a usable format.
    /// Accessing `audioEngine.inputNode` with no audio device throws an unrecoverable
    /// NSException, so we check via AVCaptureDevice first.
    private func validateAudioInput() throws -> AVAudioFormat {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw AudioCaptureError.noAudioInputDevice
        }
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.invalidAudioFormat
        }
        return inputFormat
    }

    // MARK: - Format negotiation

    /// Determine the best audio format compatible with the given transcriber module.
    /// Call this before startCapture to set up format conversion.
    func prepareFormat(compatibleWith module: SpeechTranscriber) async throws {
        let inputFormat = try validateAudioInput()
        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module]
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }

        if inputFormat.sampleRate != bestFormat.sampleRate ||
            inputFormat.channelCount != bestFormat.channelCount ||
            inputFormat.commonFormat != bestFormat.commonFormat {
            guard let conv = AVAudioConverter(from: inputFormat, to: bestFormat) else {
                throw AudioCaptureError.formatConversionFailed
            }
            converter = conv
            targetFormat = bestFormat
        } else {
            converter = nil
            targetFormat = nil
        }
    }

    // MARK: - Ducking

    /// Configure the input node to minimize ducking of other audio (e.g. music).
    /// Voice processing must be enabled for the ducking configuration to take effect;
    /// once enabled we set the ducking level to minimum so other apps stay at full volume.
    static func disableDucking(on inputNode: AudioInputDuckingConfiguring) throws {
        var node = inputNode
        try node.setVoiceProcessingEnabled(true)
        node.voiceProcessingOtherAudioDuckingConfiguration = .init(
            enableAdvancedDucking: true,
            duckingLevel: .min
        )
    }

    // MARK: - Capture

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        self.continuation = continuation

        let inputFormat = try validateAudioInput()

        // Remove any stale tap from a prior failed session to prevent
        // "tap already installed" crash on re-start.
        audioEngine.inputNode.removeTap(onBus: 0)

        // Minimize ducking of other audio while the microphone is active.
        try Self.disableDucking(on: audioEngine.inputNode)

        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self else { return }

            self.levelMonitor?.updateRMS(from: buffer)

            if let converter = self.converter, let targetFormat = self.targetFormat {
                guard let converted = self.convertBuffer(buffer, using: converter, to: targetFormat) else {
                    return
                }
                self.continuation?.yield(converted)
            } else {
                self.continuation?.yield(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        return stream
    }

    func stopCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Format conversion

    private func convertBuffer(
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

        // Use a box to avoid capturing a mutable var in a @Sendable closure
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

/// Reference type to safely pass mutable state into @Sendable converter closure
private final class ConversionState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideData = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

enum AudioCaptureError: LocalizedError {
    case formatConversionFailed
    case microphonePermissionDenied
    case noAudioInputDevice
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
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
