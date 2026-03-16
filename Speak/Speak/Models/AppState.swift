import Foundation
import Observation

enum RecordingMode {
    case hold
    case toggle
}

enum ConversationPhase {
    case idle
    case listening
    case transcribing
    case submitting
    case waitingForClaude
    case speaking
}

@MainActor
@Observable
final class AppState {
    var recordingMode: RecordingMode = .hold
    var isRecording = false
    var finalizedText = ""
    var volatileText = ""
    var error: String?
    var isModelDownloading = false
    var isPostProcessing = false
    var permissionsGranted = false
    var isPreviewing = false
    var previewText = ""
    var pasteFailedHint = false
    var audioLevel: AudioLevelMonitor?

    // MARK: - Conversation mode

    var isConversationMode = false
    var conversationPhase: ConversationPhase = .idle
    var claudeResponseText = ""

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
        isPreviewing = false
        previewText = ""
        pasteFailedHint = false
        recordingMode = .hold
    }

    func appendFinalizedText(_ text: String) {
        finalizedText += text
        volatileText = ""
    }

    func updateVolatileText(_ text: String) {
        volatileText = text
    }
}
