@preconcurrency import AVFoundation
@testable import Speak
import Testing

@Suite("AudioCaptureManager – Ducking")
struct AudioCaptureManagerDuckingTests {
    // MARK: - Mock

    private final class MockInputNode: AudioInputDuckingConfiguring {
        var voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration()
        var voiceProcessingEnabled = false
        var shouldThrow = false

        func setVoiceProcessingEnabled(_ enabled: Bool) throws {
            if shouldThrow { throw AudioCaptureError.formatConversionFailed }
            voiceProcessingEnabled = enabled
        }
    }

    // MARK: - disableDucking

    @Test
    func disableDuckingEnablesVoiceProcessing() throws {
        let node = MockInputNode()

        try AudioCaptureManager.disableDucking(on: node)

        #expect(node.voiceProcessingEnabled)
    }

    @Test
    func disableDuckingEnablesAdvancedDucking() throws {
        let node = MockInputNode()

        try AudioCaptureManager.disableDucking(on: node)

        #expect(node.voiceProcessingOtherAudioDuckingConfiguration.enableAdvancedDucking.boolValue)
    }

    @Test
    func disableDuckingSetsDuckingLevelToMin() throws {
        let node = MockInputNode()

        try AudioCaptureManager.disableDucking(on: node)

        #expect(node.voiceProcessingOtherAudioDuckingConfiguration.duckingLevel == .min)
    }

    @Test
    func disableDuckingPropagatesVoiceProcessingError() {
        let node = MockInputNode()
        node.shouldThrow = true

        #expect(throws: AudioCaptureError.self) {
            try AudioCaptureManager.disableDucking(on: node)
        }
    }

    @Test
    func disableDuckingDoesNotSetConfigWhenVoiceProcessingFails() {
        let node = MockInputNode()
        node.shouldThrow = true

        try? AudioCaptureManager.disableDucking(on: node)

        // Config should remain at default since setVoiceProcessingEnabled threw
        #expect(node.voiceProcessingOtherAudioDuckingConfiguration.duckingLevel == .default)
    }
}
