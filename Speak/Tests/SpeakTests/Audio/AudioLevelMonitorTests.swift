@preconcurrency import AVFoundation
import Testing
@testable import Speak

@Suite("AudioLevelMonitor")
struct AudioLevelMonitorTests {

    // MARK: - Helpers

    /// Create an AVAudioPCMBuffer filled with a constant amplitude value.
    private func makeBuffer(amplitude: Float, frameCount: AVAudioFrameCount = 1024) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
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
    func stopMonitoringResetsBarLevels() async throws {
        let monitor = AudioLevelMonitor()

        // Feed audio and let the monitor tick
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))
        monitor.startMonitoring()
        try await Task.sleep(for: .milliseconds(100))

        // Precondition: bars should have moved
        #expect(monitor.barLevels[0] > 0)

        // Stop should reset everything
        monitor.stopMonitoring()
        #expect(monitor.barLevels == [0, 0, 0, 0, 0])
    }

    // MARK: - Audio level detection

    @Test @MainActor
    func monitoringDetectsAudioLevel() async throws {
        let monitor = AudioLevelMonitor()

        // Feed a buffer with known amplitude (RMS of constant 0.5 = 0.5)
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))

        monitor.startMonitoring()
        try await Task.sleep(for: .milliseconds(100))

        // The newest bar should reflect the audio level
        #expect(monitor.barLevels[0] > 0)

        monitor.stopMonitoring()
    }

    @Test @MainActor
    func silenceKeepsBarsNearZero() async throws {
        let monitor = AudioLevelMonitor()

        // Feed a silent buffer (all zeros)
        monitor.updateRMS(from: makeBuffer(amplitude: 0))

        monitor.startMonitoring()
        try await Task.sleep(for: .milliseconds(100))

        // All bars should remain at zero
        for level in monitor.barLevels {
            #expect(level == 0)
        }

        monitor.stopMonitoring()
    }

    // MARK: - Bar shifting

    @Test @MainActor
    func barsShiftOverMultipleTicks() async throws {
        let monitor = AudioLevelMonitor()

        // Feed audio so the level is non-zero
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))

        monitor.startMonitoring()
        // Let several ticks happen (~6 ticks at 30Hz in 200ms)
        try await Task.sleep(for: .milliseconds(200))

        // Multiple bars should have shifted to non-zero values
        let nonZeroBars = monitor.barLevels.filter { $0 > 0 }.count
        #expect(nonZeroBars > 1)

        monitor.stopMonitoring()
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
    func updateRMSWithZeroFrameLengthIsIgnored() async throws {
        let monitor = AudioLevelMonitor()

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 0

        monitor.updateRMS(from: buffer)
        monitor.startMonitoring()
        try await Task.sleep(for: .milliseconds(100))

        // Should remain zero since the buffer had no frames
        #expect(monitor.barLevels[0] == 0)

        monitor.stopMonitoring()
    }
}
