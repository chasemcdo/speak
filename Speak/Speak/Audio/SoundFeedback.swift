import AppKit

enum SoundFeedback {
    static func playStartSound() {
        guard let url = Bundle.module.url(forResource: "record-start", withExtension: "aif") else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }

    static func playStopSound() {
        guard let url = Bundle.module.url(forResource: "record-stop", withExtension: "aif") else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }
}
