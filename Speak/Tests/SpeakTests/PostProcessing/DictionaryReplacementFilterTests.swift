import Foundation
@testable import Speak
import Testing

@Suite("DictionaryReplacementFilter")
struct DictionaryReplacementFilterTests {
    private let dummyContext = ProcessingContext(locale: .init(identifier: "en_US"))

    @Test
    func replacesNounMatchingDictionaryPhrase() async throws {
        let filter = DictionaryReplacementFilter(phrases: ["Decoda"])
        let result = try await filter.apply(to: "I talked to Dakota", context: dummyContext)
        #expect(result == "I talked to Decoda")
    }

    @Test
    func doesNotReplaceVerbs() async throws {
        // "running" is a verb — should not be replaced even if similar to a dictionary word
        let filter = DictionaryReplacementFilter(phrases: ["Runnung"])
        let result = try await filter.apply(to: "She was running quickly", context: dummyContext)
        #expect(!result.contains("Runnung"))
    }

    @Test
    func caseInsensitiveMatchInDictionary() async throws {
        // Dictionary phrase is lowercase but should still replace a capitalized noun
        let filter = DictionaryReplacementFilter(phrases: ["decoda"])
        let result = try await filter.apply(to: "I talked to Dakota", context: dummyContext)
        #expect(result == "I talked to decoda")
    }

    @Test
    func multipleReplacements() async throws {
        let filter = DictionaryReplacementFilter(phrases: ["Decoda", "Kubernetes"])
        let result = try await filter.apply(
            to: "Dakota uses Kubernetees for deployment",
            context: dummyContext
        )
        #expect(result.contains("Decoda"))
        #expect(result.contains("Kubernetes"))
    }

    @Test
    func noMatchBelowThreshold() async throws {
        // "Apple" and "Decoda" are too dissimilar
        let filter = DictionaryReplacementFilter(phrases: ["Decoda"])
        let result = try await filter.apply(to: "I ate an Apple", context: dummyContext)
        #expect(!result.contains("Decoda"))
    }

    @Test
    func emptyPhrasesReturnsOriginal() async throws {
        let filter = DictionaryReplacementFilter(phrases: [])
        let result = try await filter.apply(to: "Hello world", context: dummyContext)
        #expect(result == "Hello world")
    }

    @Test
    func exactMatchPreservesText() async throws {
        // If the word already matches the dictionary phrase exactly, don't touch it
        let filter = DictionaryReplacementFilter(phrases: ["Dakota"])
        let result = try await filter.apply(to: "I talked to Dakota", context: dummyContext)
        #expect(result == "I talked to Dakota")
    }
}
