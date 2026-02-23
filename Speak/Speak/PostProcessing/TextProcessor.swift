import Foundation
import Observation

/// A single text transformation step in the post-processing pipeline.
protocol TextFilter: Sendable {
    func apply(to text: String, context: ProcessingContext) async throws -> String
}

/// Context passed to each filter (surrounding text, locale, etc.)
struct ProcessingContext: Sendable {
    var surroundingText: String?
    var screenVocabulary: ScreenVocabulary?
    var locale: Locale
}

/// Chains filters together and runs them in sequence.
@MainActor
@Observable
final class TextProcessor {
    var isProcessing = false

    private(set) var filters: [TextFilter] = []

    func addFilter(_ filter: TextFilter) {
        filters.append(filter)
    }

    func removeAllFilters() {
        filters.removeAll()
    }

    /// Run all registered filters in sequence on the given text.
    func process(_ text: String, context: ProcessingContext) async -> String {
        guard !text.isEmpty, !filters.isEmpty else { return text }

        isProcessing = true
        defer { isProcessing = false }

        var result = text
        for filter in filters {
            do {
                result = try await filter.apply(to: result, context: context)
            } catch {
                // If a filter fails, skip it and continue with the current result
                continue
            }
        }
        return result
    }
}
