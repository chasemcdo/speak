@preconcurrency import AVFoundation
import os

@MainActor
@Observable
final class AudioLevelMonitor {
    private(set) var barLevels: [Float] = [0, 0, 0, 0, 0]

    private nonisolated let rawLevel = OSAllocatedUnfairLock(initialState: Float(0))
    private var smoothedLevel: Float = 0
    private var timer: Timer?

    /// Called from the audio tap thread — computes RMS and stores it thread-safely.
    nonisolated func updateRMS(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = channelData[0]
        var sumOfSquares: Float = 0
        for i in 0 ..< frameLength {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrtf(sumOfSquares / Float(frameLength))

        rawLevel.withLock { $0 = rms }
    }

    func startMonitoring() {
        stopMonitoring()
        // ~30Hz poll
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        smoothedLevel = 0
        barLevels = [0, 0, 0, 0, 0]
        rawLevel.withLock { $0 = 0 }
    }

    func tick() {
        let raw = rawLevel.withLock { $0 }

        // Exponential smoothing — fast attack, slower decay
        let alpha: Float = raw > smoothedLevel ? 0.4 : 0.15
        smoothedLevel += alpha * (raw - smoothedLevel)

        // Shift bars right (oldest falls off), newest enters at index 0
        barLevels.removeLast()
        barLevels.insert(smoothedLevel, at: 0)
    }
}
