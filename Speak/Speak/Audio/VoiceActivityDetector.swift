import Foundation
import Observation

@MainActor
@Observable
final class VoiceActivityDetector {
    enum Event {
        case speechStarted
        case speechEnded
    }

    /// Callback fired when voice activity state changes.
    var onEvent: ((Event) -> Void)?

    /// Whether speech is currently detected.
    private(set) var isSpeechDetected = false

    // MARK: - Configuration

    /// RMS threshold above which audio is considered speech.
    var speechThreshold: Float = 0.015
    /// Duration (seconds) RMS must stay above threshold to confirm speech start.
    var speechStartDelay: TimeInterval = 0.2
    /// Duration (seconds) RMS must stay below threshold to confirm speech end.
    var silenceTimeout: TimeInterval = 1.5

    // MARK: - Internal state

    private var aboveThresholdStart: Date?
    private var belowThresholdStart: Date?
    private var timer: Timer?
    private weak var monitor: AudioLevelMonitor?

    // MARK: - Public API

    func start(monitor: AudioLevelMonitor) {
        self.monitor = monitor
        stop()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        aboveThresholdStart = nil
        belowThresholdStart = nil
        isSpeechDetected = false
    }

    // MARK: - Tick

    private func tick() {
        guard let monitor else { return }
        let rms = monitor.currentRMS
        let now = Date()

        if rms > speechThreshold {
            belowThresholdStart = nil

            if !isSpeechDetected {
                if let start = aboveThresholdStart {
                    if now.timeIntervalSince(start) >= speechStartDelay {
                        isSpeechDetected = true
                        onEvent?(.speechStarted)
                    }
                } else {
                    aboveThresholdStart = now
                }
            }
        } else {
            aboveThresholdStart = nil

            if isSpeechDetected {
                if let start = belowThresholdStart {
                    if now.timeIntervalSince(start) >= silenceTimeout {
                        isSpeechDetected = false
                        onEvent?(.speechEnded)
                        belowThresholdStart = nil
                    }
                } else {
                    belowThresholdStart = now
                }
            }
        }
    }
}
