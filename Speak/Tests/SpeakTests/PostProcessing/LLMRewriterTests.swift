@testable import Speak
import Testing

// MARK: - Preamble stripping

struct StripPreambleTests {
    @Test func `passes through clean text`() {
        #expect(LLMRewriter.stripPreamble("Hello world.") == "Hello world.")
    }

    @Test func `strips sure here is preamble`() {
        let input = "Sure! Here is the formatted text: Hello world."
        #expect(LLMRewriter.stripPreamble(input) == "Hello world.")
    }

    @Test func `strips here is preamble without sure`() {
        let input = "Here is the formatted text: Hello world."
        #expect(LLMRewriter.stripPreamble(input) == "Hello world.")
    }

    @Test func `strips heres preamble`() {
        let input = "Here's the formatted transcript: Hello world."
        #expect(LLMRewriter.stripPreamble(input) == "Hello world.")
    }

    @Test func `strips preamble case insensitively`() {
        let input = "SURE! HERE IS THE FORMATTED TEXT: Hello world."
        #expect(LLMRewriter.stripPreamble(input) == "Hello world.")
    }

    @Test func `strips surrounding straight quotes`() {
        let input = "\"Hello world.\""
        #expect(LLMRewriter.stripPreamble(input) == "Hello world.")
    }

    @Test func `strips surrounding smart quotes`() {
        let input = "\u{201C}Hello world.\u{201D}"
        #expect(LLMRewriter.stripPreamble(input) == "Hello world.")
    }

    @Test func `strips preamble and quotes together`() {
        let input = "Sure! Here is the formatted text: \"Hello world.\""
        #expect(LLMRewriter.stripPreamble(input) == "Hello world.")
    }

    @Test func `does not strip single quote`() {
        let input = "\"Hello world."
        #expect(LLMRewriter.stripPreamble(input) == "\"Hello world.")
    }

    @Test func `does not strip quotes from short text`() {
        let input = "\""
        #expect(LLMRewriter.stripPreamble(input) == "\"")
    }

    @Test func `handles empty string`() {
        #expect(LLMRewriter.stripPreamble("") == "")
    }

    @Test func `does not strip mid-text colons`() {
        let input = "The meeting is at 3:00 PM tomorrow."
        #expect(LLMRewriter.stripPreamble(input) == "The meeting is at 3:00 PM tomorrow.")
    }
}

// MARK: - Hallucination guard

struct HallucinationGuardTests {
    @Test func `accepts normal ratio output`() {
        let result = LLMRewriter.applyHallucinationGuard(
            cleaned: "Hello world.",
            original: "um hello world"
        )
        #expect(result == "Hello world.")
    }

    @Test func `rejects empty cleaned output`() {
        let result = LLMRewriter.applyHallucinationGuard(
            cleaned: "",
            original: "Hello world."
        )
        #expect(result == "Hello world.")
    }

    @Test func `rejects output below 0.1 ratio`() {
        let result = LLMRewriter.applyHallucinationGuard(
            cleaned: "Hi",
            original: "This is a very long sentence that should not shrink to just two characters in any reasonable scenario."
        )
        #expect(result ==
            "This is a very long sentence that should not shrink to just two characters in any reasonable scenario.")
    }

    @Test func `rejects output above 3.0 ratio`() {
        let original = "Hello."
        let cleaned = String(repeating: "x", count: original.count * 4)
        let result = LLMRewriter.applyHallucinationGuard(
            cleaned: cleaned,
            original: original
        )
        #expect(result == original)
    }

    @Test func `accepts significant reduction for voice commands`() {
        // "delete that" removing a sentence — output is ~50% of input
        let result = LLMRewriter.applyHallucinationGuard(
            cleaned: "First sentence.",
            original: "First sentence. Second sentence delete that."
        )
        #expect(result == "First sentence.")
    }

    @Test func `accepts output at lower boundary`() {
        // Exactly at 0.1 ratio (10 chars cleaned / 100 chars original)
        let original = String(repeating: "a", count: 100)
        let cleaned = String(repeating: "b", count: 10)
        let result = LLMRewriter.applyHallucinationGuard(cleaned: cleaned, original: original)
        #expect(result == cleaned)
    }

    @Test func `accepts output at upper boundary`() {
        // Exactly at 3.0 ratio (30 chars cleaned / 10 chars original)
        let original = String(repeating: "a", count: 10)
        let cleaned = String(repeating: "b", count: 30)
        let result = LLMRewriter.applyHallucinationGuard(cleaned: cleaned, original: original)
        #expect(result == cleaned)
    }

    @Test func `accepts list formatting expansion`() {
        // List formatting can expand text with newlines and markers
        let original = "First buy milk second get eggs third pick up bread"
        let cleaned = "- Buy milk\n- Get eggs\n- Pick up bread"
        let result = LLMRewriter.applyHallucinationGuard(cleaned: cleaned, original: original)
        #expect(result == cleaned)
    }
}
