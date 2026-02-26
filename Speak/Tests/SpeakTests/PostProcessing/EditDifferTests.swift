@testable import Speak
import Testing

@Suite("EditDiffer")
struct EditDifferTests {
    @Test
    func identicalTextsProduceNoReplacements() {
        let text = "The meeting is at three pm"
        let result = EditDiffer.findReplacements(original: text, edited: text)
        #expect(result.isEmpty)
    }

    @Test
    func singleWordCorrectionDetected() {
        let original = "The meting is at three pm"
        let edited = "The meeting is at three pm"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.count == 1)
        #expect(result[0].original == "meting")
        #expect(result[0].replacement == "meeting")
    }

    @Test
    func capitalizationOnlyChangeFilteredOut() {
        let original = "the meeting is today"
        let edited = "The meeting is today"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.isEmpty)
    }

    @Test
    func punctuationOnlyChangeFilteredOut() {
        let original = "hello world"
        let edited = "hello, world"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.isEmpty)
    }

    @Test
    func fullRewriteProducesNoReplacements() {
        let original = "The quick brown fox jumps over the lazy dog"
        let edited = "A completely different sentence with new words entirely here"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.isEmpty)
    }

    @Test
    func shortWordsFilteredOut() {
        let original = "I am at the park"
        let edited = "I is at the park"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.isEmpty)
    }

    @Test
    func multipleCorrectionsDetected() {
        let original = "The meting with Jon is tomrrow"
        let edited = "The meeting with John is tomorrow"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.count >= 2)
        let replacements = Set(result.map(\.replacement))
        #expect(replacements.contains("meeting"))
        #expect(replacements.contains("tomorrow"))
    }

    @Test
    func dissimilarWordsFilteredOut() {
        // "cat" → "helicopter" — completely different word, should be filtered
        let original = "The cat sat here"
        let edited = "The helicopter sat here"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.isEmpty)
    }

    @Test
    func similarMisspellingDetected() {
        // "recieve" → "receive" — minor edit, should pass similarity
        let original = "Please recieve this"
        let edited = "Please receive this"
        let result = EditDiffer.findReplacements(original: original, edited: edited)
        #expect(result.count == 1)
        #expect(result[0].replacement == "receive")
    }

    @Test
    func emptyInputsProduceNoReplacements() {
        #expect(EditDiffer.findReplacements(original: "", edited: "hello").isEmpty)
        #expect(EditDiffer.findReplacements(original: "hello", edited: "").isEmpty)
        #expect(EditDiffer.findReplacements(original: "", edited: "").isEmpty)
    }
}
