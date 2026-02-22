@preconcurrency import AVFoundation
import Speech

final class AudioCaptureManager: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

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

    // MARK: - Format negotiation

    /// Determine the best audio format compatible with the given transcriber module.
    /// Call this before startCapture to set up format conversion.
    func prepareFormat(compatibleWith module: SpeechTranscriber) async throws {
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module]
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }

        if inputFormat.sampleRate != bestFormat.sampleRate ||
           inputFormat.channelCount != bestFormat.channelCount {
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

    // MARK: - Capture

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        self.continuation = continuation

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)

        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self else { return }

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
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if error != nil {
            return nil
        }
        return outputBuffer
    }
}

// Reference type to safely pass mutable state into @Sendable converter closure
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

    var errorDescription: String? {
        switch self {
        case .formatConversionFailed:
            return "Failed to convert audio format for speech recognition."
        case .microphonePermissionDenied:
            return "Microphone access is required for dictation."
        }
    }
}
