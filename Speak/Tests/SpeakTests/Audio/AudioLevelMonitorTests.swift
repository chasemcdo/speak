@preconcurrency import AVFoundation
@testable import Speak
import Testing

@Suite("AudioLevelMonitor")
struct AudioLevelMonitorTests {
    // MARK: - Helpers

    /// Create an AVAudioPCMBuffer filled with a constant amplitude value.
    private func makeBuffer(amplitude: Float, frameCount: AVAudioFrameCount = 1024) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for i in 0 ..< Int(frameCount) {
            samples[i] = amplitude
        }
        return buffer
    }

    // MARK: - Initial state

    @Test @MainActor
    func initialBarLevelsAreAllZero() {
        let monitor = AudioLevelMonitor()
        #expect(monitor.barLevels == [0, 0, 0, 0, 0])
    }

    @Test @MainActor
    func barLevelsHasFiveElements() {
        let monitor = AudioLevelMonitor()
        #expect(monitor.barLevels.count == 5)
    }

    // MARK: - Stop resets state

    @Test @MainActor
    func stopMonitoringResetsBarLevels() {
        let monitor = AudioLevelMonitor()

        // Feed audio and tick to move bars
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))
        monitor.tick()

        // Precondition: bars should have moved
        #expect(monitor.barLevels[0] > 0)

        // Stop should reset everything
        monitor.stopMonitoring()
        #expect(monitor.barLevels == [0, 0, 0, 0, 0])
    }

    // MARK: - Audio level detection

    @Test @MainActor
    func tickDetectsAudioLevel() {
        let monitor = AudioLevelMonitor()

        // Feed a buffer with known amplitude (RMS of constant 0.5 = 0.5)
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))
        monitor.tick()

        // The newest bar should reflect the audio level
        #expect(monitor.barLevels[0] > 0)
    }

    @Test @MainActor
    func silenceKeepsBarsAtZero() {
        let monitor = AudioLevelMonitor()

        // Feed a silent buffer (all zeros)
        monitor.updateRMS(from: makeBuffer(amplitude: 0))
        monitor.tick()

        // All bars should remain at zero
        for level in monitor.barLevels {
            #expect(level == 0)
        }
    }

    // MARK: - Bar shifting

    @Test @MainActor
    func barsShiftOverMultipleTicks() {
        let monitor = AudioLevelMonitor()

        // Feed audio so the level is non-zero
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))

        // Simulate several ticks
        for _ in 0 ..< 6 {
            monitor.tick()
        }

        // Multiple bars should have shifted to non-zero values
        let nonZeroBars = monitor.barLevels.filter { $0 > 0 }.count
        #expect(nonZeroBars > 1)
    }

    @Test @MainActor
    func newestBarIsAtIndexZero() {
        let monitor = AudioLevelMonitor()

        // Feed loud audio and tick once
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))
        monitor.tick()

        let firstBar = monitor.barLevels[0]
        // bar[0] should be newest (highest), bar[4] should still be zero
        #expect(firstBar > 0)
        #expect(monitor.barLevels[4] == 0)
    }

    @Test @MainActor
    func barLevelsAlwaysMaintainFiveElements() {
        let monitor = AudioLevelMonitor()

        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))
        for _ in 0 ..< 20 {
            monitor.tick()
        }

        #expect(monitor.barLevels.count == 5)
    }

    // MARK: - Smoothing behavior

    @Test @MainActor
    func smoothingProducesGradualIncrease() {
        let monitor = AudioLevelMonitor()

        // Feed a loud signal
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))

        // First tick — attack smoothing (alpha 0.4)
        monitor.tick()
        let afterFirstTick = monitor.barLevels[0]

        // Second tick — should be higher since smoothing accumulates
        monitor.tick()
        let afterSecondTick = monitor.barLevels[0]

        #expect(afterSecondTick > afterFirstTick)
    }

    // MARK: - Edge cases

    @Test @MainActor
    func startMonitoringTwiceDoesNotCrash() {
        let monitor = AudioLevelMonitor()
        monitor.startMonitoring()
        monitor.startMonitoring() // Should replace timer, not crash
        monitor.stopMonitoring()
    }

    @Test @MainActor
    func stopMonitoringWithoutStartDoesNotCrash() {
        let monitor = AudioLevelMonitor()
        monitor.stopMonitoring() // Should be safe to call without start
    }

    @Test @MainActor
    func updateRMSWithZeroFrameLengthIsIgnored() throws {
        let monitor = AudioLevelMonitor()

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 0

        monitor.updateRMS(from: buffer)
        monitor.tick()

        // Should remain zero since the buffer had no frames
        #expect(monitor.barLevels[0] == 0)
    }
}
