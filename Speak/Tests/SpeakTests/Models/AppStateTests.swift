@testable import Speak
import Testing

struct AppStateTests {
    @Test @MainActor func `display text combines finalized and volatile`() {
        let state = AppState()
        state.finalizedText = "Hello "
        state.volatileText = "world"
        #expect(state.displayText == "Hello world")
    }

    @Test @MainActor func `display text empty by default`() {
        let state = AppState()
        #expect(state.displayText == "")
    }

    @Test @MainActor func `has text is false when empty`() {
        let state = AppState()
        #expect(state.hasText == false)
    }

    @Test @MainActor func `has text is true with finalized text`() {
        let state = AppState()
        state.finalizedText = "Hello"
        #expect(state.hasText == true)
    }

    @Test @MainActor func `has text is true with volatile text only`() {
        let state = AppState()
        state.volatileText = "typing..."
        #expect(state.hasText == true)
    }

    @Test @MainActor func `reset clears all state`() {
        let state = AppState()
        state.isRecording = true
        state.finalizedText = "Hello"
        state.volatileText = "world"
        state.error = "Some error"
        state.isPreviewing = true
        state.previewText = "Preview text"
        state.recordingMode = .toggle

        state.reset()

        #expect(state.isRecording == false)
        #expect(state.finalizedText == "")
        #expect(state.volatileText == "")
        #expect(state.error == nil)
        #expect(state.isPreviewing == false)
        #expect(state.previewText == "")
        #expect(state.recordingMode == .hold)
    }

    @Test @MainActor func `append finalized text appends and clears volatile`() {
        let state = AppState()
        state.volatileText = "partial"
        state.appendFinalizedText("Hello ")
        #expect(state.finalizedText == "Hello ")
        #expect(state.volatileText == "")
    }

    @Test @MainActor func `append finalized text accumulates`() {
        let state = AppState()
        state.appendFinalizedText("Hello ")
        state.appendFinalizedText("world")
        #expect(state.finalizedText == "Hello world")
    }

    @Test @MainActor func `update volatile text sets volatile`() {
        let state = AppState()
        state.updateVolatileText("typing...")
        #expect(state.volatileText == "typing...")
    }

    // MARK: - Paste-failed hint

    @Test @MainActor func `reset clears paste failed hint`() {
        let state = AppState()
        state.pasteFailedHint = true

        state.reset()

        #expect(state.pasteFailedHint == false)
    }

    // MARK: - Suggested word

    @Test @MainActor func suggestedWordDefaultsToNil() {
        let state = AppState()
        #expect(state.suggestedWord == nil)
    }

    @Test @MainActor func resetClearsSuggestedWord() {
        let state = AppState()
        state.suggestedWord = DictionarySuggestion(phrase: "gRPC", original: "grpc")

        state.reset()

        #expect(state.suggestedWord == nil)
    }

    // MARK: - Preview state

    @Test @MainActor func `preview state defaults to false`() {
        let state = AppState()
        #expect(state.isPreviewing == false)
        #expect(state.previewText == "")
    }

    @Test @MainActor func `reset clears preview state`() {
        let state = AppState()
        state.isPreviewing = true
        state.previewText = "Hello world"

        state.reset()

        #expect(state.isPreviewing == false)
        #expect(state.previewText == "")
    }

    // MARK: - Recording mode

    @Test @MainActor func `recording mode defaults to hold`() {
        let state = AppState()
        #expect(state.recordingMode == .hold)
    }

    @Test @MainActor func `reset clears recording mode`() {
        let state = AppState()
        state.recordingMode = .toggle

        state.reset()

        #expect(state.recordingMode == .hold)
    }
}
