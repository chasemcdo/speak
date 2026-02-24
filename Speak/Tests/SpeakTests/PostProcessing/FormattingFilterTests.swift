import Testing
@testable import Speak

private let filter = FormattingFilter()
private let ctx = ProcessingContext(locale: .current)

private func formatted(_ text: String) async throws -> String {
    try await filter.apply(to: text, context: ctx)
}

@Suite("FormattingFilter")
struct FormattingFilterTests {

    // -- Sentence capitalization --

    @Test func capitalizesFirstCharacter() async throws {
        #expect(try await formatted("hello world.") == "Hello world.")
    }

    @Test func capitalizesAfterPeriod() async throws {
        #expect(try await formatted("first sentence. second sentence.") == "First sentence. Second sentence.")
    }

    @Test func capitalizesAfterExclamation() async throws {
        #expect(try await formatted("wow! that's great.") == "Wow! That's great.")
    }

    @Test func capitalizesAfterQuestion() async throws {
        #expect(try await formatted("really? yes it is.") == "Really? Yes it is.")
    }

    @Test func preservesAlreadyCapitalized() async throws {
        #expect(try await formatted("Hello World.") == "Hello World.")
    }

    // -- Smart punctuation --

    @Test func tripleDotsToEllipsis() async throws {
        #expect(try await formatted("Wait... really?") == "Wait\u{2026} Really?")
    }

    @Test func doubleHyphensToEmDash() async throws {
        #expect(try await formatted("The answer--yes.") == "The answer\u{2014}yes.")
    }

    // -- Whitespace cleanup --

    @Test func collapsesMultipleSpaces() async throws {
        #expect(try await formatted("Hello   world.") == "Hello world.")
    }

    @Test func trimsLeadingAndTrailing() async throws {
        #expect(try await formatted("  Hello world.  ") == "Hello world.")
    }

    // -- Edge cases --

    @Test func emptyStringPassesThrough() async throws {
        #expect(try await formatted("") == "")
    }

    @Test func singleCharacter() async throws {
        #expect(try await formatted("a") == "A")
    }

    @Test func allTransformsTogether() async throws {
        // Note: capitalization runs before whitespace trimming, so leading-space
        // inputs won't have their first letter capitalized — that's current behavior.
        let input = "hello world...  this is--a test.   and more."
        let result = try await formatted(input)
        #expect(result == "Hello world\u{2026} This is\u{2014}a test. And more.")
    }
}
