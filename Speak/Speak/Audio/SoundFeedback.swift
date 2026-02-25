import AppKit

enum SoundFeedback {
    static func playStartSound() {
        NSSound(named: "record-start")?.play()
    }

    static func playStopSound() {
        NSSound(named: "record-stop")?.play()
    }
}
