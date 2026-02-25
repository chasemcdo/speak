import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var isRecording = false
    var finalizedText = ""
    var volatileText = ""
    var error: String?
    var isModelDownloading = false
    var isPostProcessing = false
    var permissionsGranted = false
    var audioLevel: AudioLevelMonitor?

    var displayText: String {
        finalizedText + volatileText
    }

    var hasText: Bool {
        !displayText.isEmpty
    }

    func reset() {
        isRecording = false
        finalizedText = ""
        volatileText = ""
        error = nil
    }

    func appendFinalizedText(_ text: String) {
        finalizedText += text
        volatileText = ""
    }

    func updateVolatileText(_ text: String) {
        volatileText = text
    }
}
