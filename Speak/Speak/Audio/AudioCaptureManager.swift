@preconcurrency import AVFoundation
import CoreMedia
import Speech

final class AudioCaptureManager: @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private let outputDelegate = CaptureOutputDelegate()
    private let captureQueue = DispatchQueue(label: "com.speak.audio-capture", qos: .userInteractive)

    var levelMonitor: AudioLevelMonitor? {
        get { outputDelegate.levelMonitor }
        set { outputDelegate.levelMonitor = newValue }
    }

    var isCapturing: Bool {
        captureSession.isRunning
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
    private func validateAudioInput() throws -> AVCaptureDevice {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw AudioCaptureError.noAudioInputDevice
        }
        return device
    }

    // MARK: - Format negotiation

    /// Determine the best audio format compatible with the given transcriber module.
    /// Call this before startCapture to set up format conversion.
    func prepareFormat(compatibleWith module: SpeechTranscriber) async throws {
        _ = try validateAudioInput()
        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module]
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }
        outputDelegate.targetFormat = bestFormat
    }

    // MARK: - Capture

    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        let device = try validateAudioInput()

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        outputDelegate.continuation = continuation
        outputDelegate.converter = nil

        captureSession.beginConfiguration()

        // Remove stale inputs/outputs from a prior session.
        for input in captureSession.inputs { captureSession.removeInput(input) }
        for output in captureSession.outputs { captureSession.removeOutput(output) }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw AudioCaptureError.noAudioInputDevice
        }
        captureSession.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: true,
        ]
        output.setSampleBufferDelegate(outputDelegate, queue: captureQueue)
        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            throw AudioCaptureError.invalidAudioFormat
        }
        captureSession.addOutput(output)

        captureSession.commitConfiguration()

        // Apple docs: don't call startRunning() on main thread.
        captureQueue.async { [captureSession] in
            captureSession.startRunning()
        }

        return stream
    }

    func stopCapture() {
        captureSession.stopRunning()
        outputDelegate.continuation?.finish()
        outputDelegate.continuation = nil
        outputDelegate.converter = nil
    }
}

// MARK: - CaptureOutputDelegate

private final class CaptureOutputDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    var converter: AVAudioConverter?
    var targetFormat: AVAudioFormat?
    var levelMonitor: AudioLevelMonitor?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let rawBuffer = sampleBuffer.toPCMBuffer() else { return }

        levelMonitor?.updateRMS(from: rawBuffer)

        guard let targetFormat else {
            continuation?.yield(rawBuffer)
            return
        }

        // Lazily create converter on first buffer when the capture format is known.
        if converter == nil {
            if rawBuffer.format.sampleRate == targetFormat.sampleRate,
               rawBuffer.format.channelCount == targetFormat.channelCount,
               rawBuffer.format.commonFormat == targetFormat.commonFormat
            {
                // Formats match — no conversion needed.
                continuation?.yield(rawBuffer)
                return
            }
            guard let conv = AVAudioConverter(from: rawBuffer.format, to: targetFormat) else { return }
            converter = conv
        }

        guard let converter, let converted = convertBuffer(rawBuffer, using: converter, to: targetFormat) else {
            return
        }
        continuation?.yield(converted)
    }

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

/// Reference type to safely pass mutable state into @Sendable converter closure
private final class ConversionState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideData = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer

extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = formatDescription,
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return nil }

        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frameCount > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }

        pcm.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frameCount), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}

// MARK: - Errors

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
