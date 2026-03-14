@testable import Speak
import Testing

// MARK: - Mock

@MainActor
private final class MockSpeechSynthesizer: SpeechSynthesizing {
    var speakCalled = false
    var spokenText: String?
    var stopCalled = false
    var isSpeaking = false

    func speak(_ text: String) async {
        speakCalled = true
        spokenText = text
        isSpeaking = true
        // Simulate speech completing immediately
        isSpeaking = false
    }

    func stop() {
        stopCalled = true
        isSpeaking = false
    }
}

@Suite
struct SpeechSynthesizerTests {
    @Test @MainActor
    func `mock speak sets spoken text`() async {
        let mock = MockSpeechSynthesizer()
        await mock.speak("Hello world")
        #expect(mock.speakCalled)
        #expect(mock.spokenText == "Hello world")
    }

    @Test @MainActor
    func `mock is not speaking after completion`() async {
        let mock = MockSpeechSynthesizer()
        await mock.speak("Test")
        #expect(!mock.isSpeaking)
    }

    @Test @MainActor
    func `mock stop sets flag`() {
        let mock = MockSpeechSynthesizer()
        mock.isSpeaking = true
        mock.stop()
        #expect(mock.stopCalled)
        #expect(!mock.isSpeaking)
    }

    @Test @MainActor
    func `mock stop without speaking is safe`() {
        let mock = MockSpeechSynthesizer()
        mock.stop()
        #expect(mock.stopCalled)
        #expect(!mock.isSpeaking)
    }

    @Test @MainActor
    func `service initial state is not speaking`() {
        let service = SpeechSynthesizerService()
        #expect(!service.isSpeaking)
    }

    @Test @MainActor
    func `service stop without speaking is safe`() {
        let service = SpeechSynthesizerService()
        service.stop() // Should not crash
        #expect(!service.isSpeaking)
    }
}
