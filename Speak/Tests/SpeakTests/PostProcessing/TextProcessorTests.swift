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

@Suite("TextProcessor")
struct TextProcessorTests {
    @Test @MainActor func chainsFiltersInOrder() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())
        processor.addFilter(SuffixFilter(suffix: "!"))

        let result = await processor.process("hello", context: ctx)
        #expect(result == "HELLO!")
    }

    @Test @MainActor func emptyInputReturnsEmpty() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())

        let result = await processor.process("", context: ctx)
        #expect(result == "")
    }

    @Test @MainActor func noFiltersReturnsInput() async {
        let processor = TextProcessor()

        let result = await processor.process("hello", context: ctx)
        #expect(result == "hello")
    }

    @Test @MainActor func throwingFilterIsSkipped() async {
        let processor = TextProcessor()
        processor.addFilter(ThrowingFilter())
        processor.addFilter(UppercaseFilter())

        let result = await processor.process("hello", context: ctx)
        #expect(result == "HELLO")
    }

    @Test @MainActor func isProcessingResetsAfterCompletion() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())

        #expect(processor.isProcessing == false)
        _ = await processor.process("hello", context: ctx)
        #expect(processor.isProcessing == false)
    }

    @Test @MainActor func removeAllFiltersClearsFilters() async {
        let processor = TextProcessor()
        processor.addFilter(UppercaseFilter())
        processor.removeAllFilters()

        let result = await processor.process("hello", context: ctx)
        #expect(result == "hello")
    }
}
