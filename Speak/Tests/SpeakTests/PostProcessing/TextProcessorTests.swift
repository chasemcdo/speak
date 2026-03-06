@testable import Speak
import Testing

/// A filter that uppercases all text (for testing).
private struct UppercaseFilter: TextFilter {
    func apply(to text: String, context: ProcessingContext) async throws -> String {
        text.uppercased()
    }
}

/// A filter that always throws (for testing error handling).
private struct ThrowingFilter: TextFilter {
    struct FilterError: Error {}
    func apply(to text: String, context: ProcessingContext) async throws -> String {
        throw FilterError()
    }
}

/// A filter that appends a suffix (for testing chaining).
private struct SuffixFilter: TextFilter {
    let suffix: String
    func apply(to text: String, context: ProcessingContext) async throws -> String {
        text + suffix
    }
}

private let ctx = ProcessingContext(locale: .current)

struct TextProcessorTests {
    @Test @MainActor func `chains filters in order`() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())
        processor.addFilter(SuffixFilter(suffix: "!"))

        let result = await processor.process("hello", context: ctx)
        #expect(result == "HELLO!")
    }

    @Test @MainActor func `empty input returns empty`() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())

        let result = await processor.process("", context: ctx)
        #expect(result == "")
    }

    @Test @MainActor func `no filters returns input`() async {
        let processor = TextProcessor()

        let result = await processor.process("hello", context: ctx)
        #expect(result == "hello")
    }

    @Test @MainActor func `throwing filter is skipped`() async {
        let processor = TextProcessor()
        processor.addFilter(ThrowingFilter())
        processor.addFilter(UppercaseFilter())

        let result = await processor.process("hello", context: ctx)
        #expect(result == "HELLO")
    }

    @Test @MainActor func `is processing resets after completion`() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())

        #expect(processor.isProcessing == false)
        _ = await processor.process("hello", context: ctx)
        #expect(processor.isProcessing == false)
    }

    @Test @MainActor func `remove all filters clears filters`() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())
        processor.removeAllFilters()

        let result = await processor.process("hello", context: ctx)
        #expect(result == "hello")
    }
}
