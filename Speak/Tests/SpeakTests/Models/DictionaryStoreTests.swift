import Foundation
@testable import Speak
import Testing

@Suite("DictionaryStore", .serialized)
struct DictionaryStoreTests {
    @MainActor
    private func freshStore() -> DictionaryStore {
        let store = DictionaryStore()
        store.clearAll()
        // Also clear suggestions by dismissing all
        for suggestion in store.suggestions {
            store.dismissSuggestion(suggestion)
        }
        return store
    }

    // MARK: - Codable round-trip

    @Test
    func dictionaryEntryCodableRoundTrip() throws {
        let entry = DictionaryEntry(phrase: "Kubernetes", source: .learned)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DictionaryEntry.self, from: data)
        #expect(decoded.id == entry.id)
        #expect(decoded.phrase == entry.phrase)
        #expect(decoded.source == entry.source)
    }

    @Test
    func dictionarySuggestionCodableRoundTrip() throws {
        let suggestion = DictionarySuggestion(phrase: "Kubernetes", original: "Koobernetties")
        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(DictionarySuggestion.self, from: data)
        #expect(decoded.id == suggestion.id)
        #expect(decoded.phrase == suggestion.phrase)
        #expect(decoded.original == suggestion.original)
    }

    // MARK: - Entries

    @Test @MainActor
    func addAndRemoveEntries() {
        let store = freshStore()
        store.add("Kubernetes")
        store.add("gRPC")
        #expect(store.entries.count == 2)
        #expect(store.entries[0].phrase == "gRPC")
        #expect(store.entries[1].phrase == "Kubernetes")

        store.remove(at: IndexSet(integer: 0))
        #expect(store.entries.count == 1)
        #expect(store.entries[0].phrase == "Kubernetes")
    }

    @Test @MainActor
    func clearAllEntries() {
        let store = freshStore()
        store.add("Alpha")
        store.add("Beta")
        store.clearAll()
        #expect(store.entries.isEmpty)
    }

    @Test @MainActor
    func duplicateEntryIgnored() {
        let store = freshStore()
        store.add("Kubernetes")
        store.add("kubernetes") // same word, different case
        #expect(store.entries.count == 1)
    }

    @Test @MainActor
    func emptyPhraseIgnored() {
        let store = freshStore()
        store.add("")
        #expect(store.entries.isEmpty)
    }

    // MARK: - Suggestions

    @Test @MainActor
    func acceptSuggestionAddsEntry() {
        let store = freshStore()
        let suggestion = DictionarySuggestion(phrase: "Kubernetes", original: "Koobernetties")
        store.addSuggestion(suggestion)
        #expect(store.suggestions.count == 1)

        store.acceptSuggestion(suggestion)
        #expect(store.suggestions.isEmpty)
        #expect(store.entries.count == 1)
        #expect(store.entries[0].phrase == "Kubernetes")
        #expect(store.entries[0].source == .learned)
    }

    @Test @MainActor
    func dismissSuggestionRemovesIt() {
        let store = freshStore()
        let suggestion = DictionarySuggestion(phrase: "Kubernetes", original: "Koobernetties")
        store.addSuggestion(suggestion)

        store.dismissSuggestion(suggestion)
        #expect(store.suggestions.isEmpty)
        #expect(store.entries.isEmpty)
    }

    @Test @MainActor
    func duplicateSuggestionIgnored() {
        let store = freshStore()
        let suggestion1 = DictionarySuggestion(phrase: "Kubernetes", original: "Koobernetties")
        let suggestion2 = DictionarySuggestion(phrase: "kubernetes", original: "koober")
        store.addSuggestion(suggestion1)
        store.addSuggestion(suggestion2)
        #expect(store.suggestions.count == 1)
    }

    @Test @MainActor
    func maxSuggestionsCap() {
        let store = freshStore()
        for idx in 0 ..< 60 {
            store.addSuggestion(DictionarySuggestion(
                phrase: "word\(idx)", original: "wrd\(idx)"
            ))
        }
        #expect(store.suggestions.count == 50)
    }

    @Test @MainActor
    func acceptSuggestionSkipsDuplicateEntry() {
        let store = freshStore()
        store.add("Kubernetes")
        let suggestion = DictionarySuggestion(phrase: "kubernetes", original: "Koobernetties")
        store.addSuggestion(suggestion)

        store.acceptSuggestion(suggestion)
        // Should not duplicate the entry (case-insensitive match)
        #expect(store.entries.count == 1)
        #expect(store.suggestions.isEmpty)
    }

    // MARK: - Phrases computed property

    @Test @MainActor
    func phrasesReturnsAllEntryPhrases() {
        let store = freshStore()
        store.add("Alpha")
        store.add("Beta")
        #expect(store.phrases.count == 2)
        #expect(store.phrases.contains("Alpha"))
        #expect(store.phrases.contains("Beta"))
    }

    // MARK: - Max entries cap

    @Test @MainActor
    func maxEntriesCap() {
        let store = freshStore()
        for i in 0 ..< 510 {
            store.add("word\(i)")
        }
        #expect(store.entries.count == 500)
    }
}
