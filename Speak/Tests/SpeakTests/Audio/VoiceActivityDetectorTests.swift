@preconcurrency import AVFoundation
@testable import Speak
import Testing

@Suite(.serialized)
struct VoiceActivityDetectorTests {
    // MARK: - Helpers

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
    func `initial state is no speech detected`() {
        let vad = VoiceActivityDetector()
        #expect(!vad.isSpeechDetected)
    }

    // MARK: - Speech detection

    @Test @MainActor
    func `sustained loud audio triggers speech started`() async throws {
        let monitor = AudioLevelMonitor()
        let vad = VoiceActivityDetector()
        vad.speechStartDelay = 0.05 // Shorter for testing
        vad.speechThreshold = 0.01

        var events: [VoiceActivityDetector.Event] = []
        vad.onEvent = { events.append($0) }
        vad.start(monitor: monitor)

        // Feed loud audio (RMS persists in monitor's lock)
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))

        // Wait for detection — generous margin for slow CI runners
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(20))
            if events.contains(.speechStarted) { break }
        }

        vad.stop()
        #expect(events.contains(.speechStarted))
    }

    @Test @MainActor
    func `brief loud audio does not trigger speech started`() async throws {
        let monitor = AudioLevelMonitor()
        let vad = VoiceActivityDetector()
        vad.speechStartDelay = 0.2
        vad.speechThreshold = 0.01

        var events: [VoiceActivityDetector.Event] = []
        vad.onEvent = { events.append($0) }
        vad.start(monitor: monitor)

        // Feed loud audio briefly
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))
        try await Task.sleep(for: .milliseconds(50))

        // Go silent before speechStartDelay
        monitor.updateRMS(from: makeBuffer(amplitude: 0.0))
        try await Task.sleep(for: .milliseconds(200))

        vad.stop()
        #expect(!events.contains(.speechStarted))
    }

    @Test @MainActor
    func `silence after speech triggers speech ended`() async throws {
        let monitor = AudioLevelMonitor()
        let vad = VoiceActivityDetector()
        vad.speechStartDelay = 0.05
        vad.silenceTimeout = 0.1
        vad.speechThreshold = 0.01

        var events: [VoiceActivityDetector.Event] = []
        vad.onEvent = { events.append($0) }
        vad.start(monitor: monitor)

        // Start speech — poll until detected
        monitor.updateRMS(from: makeBuffer(amplitude: 0.5))
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(20))
            if events.contains(.speechStarted) { break }
        }

        // Go silent — poll until ended
        monitor.updateRMS(from: makeBuffer(amplitude: 0.0))
        for _ in 0 ..< 50 {
            try await Task.sleep(for: .milliseconds(20))
            if events.contains(.speechEnded) { break }
        }

        vad.stop()
        #expect(events.contains(.speechStarted))
        #expect(events.contains(.speechEnded))
    }

    @Test @MainActor
    func `silence without prior speech does not trigger event`() async throws {
        let monitor = AudioLevelMonitor()
        let vad = VoiceActivityDetector()
        vad.silenceTimeout = 0.05

        var events: [VoiceActivityDetector.Event] = []
        vad.onEvent = { events.append($0) }
        vad.start(monitor: monitor)

        monitor.updateRMS(from: makeBuffer(amplitude: 0.0))
        try await Task.sleep(for: .milliseconds(150))

        vad.stop()
        #expect(events.isEmpty)
    }

    @Test @MainActor
    func `stop resets state`() {
        let monitor = AudioLevelMonitor()
        let vad = VoiceActivityDetector()
        vad.start(monitor: monitor)
        vad.stop()
        #expect(!vad.isSpeechDetected)
    }

    // MARK: - currentRMS accessor on AudioLevelMonitor

    @Test @MainActor
    func `audio level monitor exposes current RMS`() {
        let monitor = AudioLevelMonitor()
        let buffer = makeBuffer(amplitude: 0.5)
        monitor.updateRMS(from: buffer)
        #expect(monitor.currentRMS > 0)
    }

    @Test @MainActor
    func `audio level monitor current RMS is zero initially`() {
        let monitor = AudioLevelMonitor()
        #expect(monitor.currentRMS == 0)
    }
}
