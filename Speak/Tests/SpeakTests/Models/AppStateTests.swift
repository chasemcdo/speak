import Testing
@testable import Speak

@Suite("AppState")
struct AppStateTests {

    @Test @MainActor func displayTextCombinesFinalizedAndVolatile() {
        let state = AppState()
        state.finalizedText = "Hello "
        state.volatileText = "world"
        #expect(state.displayText == "Hello world")
    }

    @Test @MainActor func displayTextEmptyByDefault() {
        let state = AppState()
        #expect(state.displayText == "")
    }

    @Test @MainActor func hasTextIsFalseWhenEmpty() {
        let state = AppState()
        #expect(state.hasText == false)
    }

    @Test @MainActor func hasTextIsTrueWithFinalizedText() {
        let state = AppState()
        state.finalizedText = "Hello"
        #expect(state.hasText == true)
    }

    @Test @MainActor func hasTextIsTrueWithVolatileTextOnly() {
        let state = AppState()
        state.volatileText = "typing..."
        #expect(state.hasText == true)
    }

    @Test @MainActor func resetClearsAllState() {
        let state = AppState()
        state.isRecording = true
        state.finalizedText = "Hello"
        state.volatileText = "world"
        state.error = "Some error"

        state.reset()

        #expect(state.isRecording == false)
        #expect(state.finalizedText == "")
        #expect(state.volatileText == "")
        #expect(state.error == nil)
    }

    @Test @MainActor func appendFinalizedTextAppendsAndClearsVolatile() {
        let state = AppState()
        state.volatileText = "partial"
        state.appendFinalizedText("Hello ")
        #expect(state.finalizedText == "Hello ")
        #expect(state.volatileText == "")
    }

    @Test @MainActor func appendFinalizedTextAccumulates() {
        let state = AppState()
        state.appendFinalizedText("Hello ")
        state.appendFinalizedText("world")
        #expect(state.finalizedText == "Hello world")
    }

    @Test @MainActor func updateVolatileTextSetsVolatile() {
        let state = AppState()
        state.updateVolatileText("typing...")
        #expect(state.volatileText == "typing...")
    }

    // MARK: - Preview state

    @Test @MainActor func previewStateDefaultsToFalse() {
        let state = AppState()
        #expect(state.isDismissedPreview == false)
        #expect(state.previewText == "")
    }

    @Test @MainActor func resetClearsPreviewState() {
        let state = AppState()
        state.isDismissedPreview = true
        state.previewText = "Hello world"

        state.reset()

        #expect(state.isDismissedPreview == false)
        #expect(state.previewText == "")
    }

    @Test @MainActor func resetClearsAllStateIncludingPreview() {
        let state = AppState()
        state.isRecording = true
        state.finalizedText = "Hello"
        state.volatileText = "world"
        state.error = "Some error"
        state.isDismissedPreview = true
        state.previewText = "Preview text"

        state.reset()

        #expect(state.isRecording == false)
        #expect(state.finalizedText == "")
        #expect(state.volatileText == "")
        #expect(state.error == nil)
        #expect(state.isDismissedPreview == false)
        #expect(state.previewText == "")
    }
}
