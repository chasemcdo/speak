@preconcurrency import AVFoundation
import CoreMedia
@testable import Speak
import Testing

@Suite("AudioCaptureManager – CMSampleBuffer conversion")
struct AudioCaptureManagerSampleBufferTests {
    /// Create a CMSampleBuffer filled with a known sine-wave pattern so we can
    /// verify that `toPCMBuffer()` faithfully copies all samples.
    @Test
    func toPCMBufferConvertsAllSamples() throws {
        let sampleRate: Double = 48_000
        let frameCount: Int = 1024
        let channels: UInt32 = 1

        // Build an AudioStreamBasicDescription for Float32, non-interleaved mono.
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        let formatDesc = try {
            var desc: CMAudioFormatDescription?
            let status = CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &desc
            )
            guard status == noErr, let desc else {
                throw AudioCaptureError.invalidAudioFormat
            }
            return desc
        }()

        // Fill sample data with a recognisable pattern (index / frameCount).
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0 ..< frameCount {
            samples[i] = Float(i) / Float(frameCount)
        }

        let sampleBuffer: CMSampleBuffer = try samples.withUnsafeBytes { rawBuf in
            let blockBuffer = try {
                var bb: CMBlockBuffer?
                let status = CMBlockBufferCreateWithMemoryBlock(
                    allocator: kCFAllocatorDefault,
                    memoryBlock: nil,
                    blockLength: rawBuf.count,
                    blockAllocator: kCFAllocatorDefault,
                    customBlockSource: nil,
                    offsetToData: 0,
                    dataLength: rawBuf.count,
                    flags: 0,
                    blockBufferOut: &bb
                )
                guard status == noErr, let bb else {
                    throw AudioCaptureError.invalidAudioFormat
                }
                return bb
            }()

            let replaceStatus = CMBlockBufferReplaceDataBytes(
                with: rawBuf.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: rawBuf.count
            )
            guard replaceStatus == noErr else {
                throw AudioCaptureError.invalidAudioFormat
            }

            var sb: CMSampleBuffer?
            let sbStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                formatDescription: formatDesc,
                sampleCount: frameCount,
                presentationTimeStamp: .zero,
                packetDescriptions: nil,
                sampleBufferOut: &sb
            )
            guard sbStatus == noErr, let sb else {
                throw AudioCaptureError.invalidAudioFormat
            }
            return sb
        }

        // Convert and verify.
        let pcm = sampleBuffer.toPCMBuffer()
        let pcmBuffer = try #require(pcm, "toPCMBuffer() returned nil")

        #expect(Int(pcmBuffer.frameLength) == frameCount)
        #expect(pcmBuffer.format.sampleRate == sampleRate)
        #expect(pcmBuffer.format.channelCount == channels)

        let channelData = try #require(pcmBuffer.floatChannelData, "Expected Float32 channel data")
        for i in 0 ..< frameCount {
            let expected = Float(i) / Float(frameCount)
            #expect(
                abs(channelData[0][i] - expected) < 1e-6,
                "Sample \(i): got \(channelData[0][i]), expected \(expected)"
            )
        }
    }
}
