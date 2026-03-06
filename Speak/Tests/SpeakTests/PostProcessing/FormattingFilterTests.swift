@testable import Speak
import Testing

private let filter = FormattingFilter()
private let ctx = ProcessingContext(locale: .current)

private func formatted(_ text: String) async throws -> String {
    try await filter.apply(to: text, context: ctx)
}

struct FormattingFilterTests {
    // -- Sentence capitalization --

    @Test func `capitalizes first character`() async throws {
        #expect(try await formatted("hello world.") == "Hello world.")
    }

    @Test func `capitalizes after period`() async throws {
        #expect(try await formatted("first sentence. second sentence.") == "First sentence. Second sentence.")
    }

    @Test func `capitalizes after exclamation`() async throws {
        #expect(try await formatted("wow! that's great.") == "Wow! That's great.")
    }

    @Test func `capitalizes after question`() async throws {
        #expect(try await formatted("really? yes it is.") == "Really? Yes it is.")
    }

    @Test func `preserves already capitalized`() async throws {
        #expect(try await formatted("Hello World.") == "Hello World.")
    }

    // -- Smart punctuation --

    @Test func `triple dots to ellipsis`() async throws {
        #expect(try await formatted("Wait... really?") == "Wait\u{2026} Really?")
    }

    @Test func `double hyphens to em dash`() async throws {
        #expect(try await formatted("The answer--yes.") == "The answer\u{2014}yes.")
    }

    // -- Whitespace cleanup --

    @Test func `collapses multiple spaces`() async throws {
        #expect(try await formatted("Hello   world.") == "Hello world.")
    }

    @Test func `trims leading and trailing`() async throws {
        #expect(try await formatted("  Hello world.  ") == "Hello world.")
    }

    // -- Edge cases --

    @Test func `empty string passes through`() async throws {
        #expect(try await formatted("") == "")
    }

    @Test func `single character`() async throws {
        #expect(try await formatted("a") == "A")
    }

    @Test func `all transforms together`() async throws {
        // Note: capitalization runs before whitespace trimming, so leading-space
        // inputs won't have their first letter capitalized — that's current behavior.
        let input = "hello world...  this is--a test.   and more."
        let result = try await formatted(input)
        #expect(result == "Hello world\u{2026} This is\u{2014}a test. And more.")
    }
}
