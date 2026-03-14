import Foundation
import Observation

enum RecordingMode {
    case hold
    case toggle
}

enum OverlayMode {
    case recording
    case preview(String)
    case pasteFailed
    case suggestion(DictionarySuggestion)
    case idle
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
    var suggestedWord: DictionarySuggestion?
    var audioLevel: AudioLevelMonitor?

    var overlayMode: OverlayMode {
        if let suggestion = suggestedWord {
            return .suggestion(suggestion)
        } else if pasteFailedHint {
            return .pasteFailed
        } else if isPreviewing {
            return .preview(previewText)
        } else if isRecording {
            return .recording
        } else {
            return .idle
        }
    }

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
        suggestedWord = nil
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
