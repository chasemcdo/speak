import AppKit

enum SoundFeedback {
    private static let startSound: NSSound? = {
        guard let url = Bundle.module.url(forResource: "record-start", withExtension: "aif") else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }()

    private static let stopSound: NSSound? = {
        guard let url = Bundle.module.url(forResource: "record-stop", withExtension: "aif") else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }()

    static func playStartSound() {
        startSound?.play()
    }

    static func playStopSound() {
        stopSound?.play()
    }

    static func playPasteFailedSound() {
        NSSound(named: "Funk")?.play()
    }
}
