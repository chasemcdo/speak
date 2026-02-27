import Foundation
import Observation

struct DictionaryEntry: Codable, Identifiable {
    var id = UUID()
    var phrase: String
    var addedAt = Date()
    var source: Source = .manual

    enum Source: String, Codable {
        case manual
        case learned
    }
}

struct DictionarySuggestion: Codable, Identifiable {
    var id = UUID()
    var phrase: String
    var original: String
    var detectedAt = Date()
}

@MainActor
@Observable
final class DictionaryStore {
    private(set) var entries: [DictionaryEntry] = []
    private(set) var suggestions: [DictionarySuggestion] = []

    private static let maxEntries = 500
    private static let maxSuggestions = 50

    private let entriesFileURL: URL
    private let suggestionsFileURL: URL

    private static var defaultStorageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Speak", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(storageDirectory: URL? = nil) {
        let dir = storageDirectory ?? Self.defaultStorageDirectory
        if let storageDirectory {
            try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
        entriesFileURL = dir.appendingPathComponent("dictionary.json")
        suggestionsFileURL = dir.appendingPathComponent("suggestions.json")
        loadEntries()
        loadSuggestions()
    }

    // MARK: - Entries

    func add(_ phrase: String, source: DictionaryEntry.Source = .manual) {
        guard !phrase.isEmpty else { return }
        // Avoid duplicates
        guard !entries.contains(where: { $0.phrase.lowercased() == phrase.lowercased() }) else { return }
        entries.insert(DictionaryEntry(phrase: phrase, source: source), at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        saveEntries()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        saveEntries()
    }

    func clearAll() {
        entries.removeAll()
        saveEntries()
    }

    // MARK: - Suggestions

    func addSuggestion(_ suggestion: DictionarySuggestion) {
        // Avoid duplicate suggestions for the same phrase
        guard !suggestions.contains(where: { $0.phrase.lowercased() == suggestion.phrase.lowercased() }) else { return }
        suggestions.insert(suggestion, at: 0)
        if suggestions.count > Self.maxSuggestions {
            suggestions = Array(suggestions.prefix(Self.maxSuggestions))
        }
        saveSuggestions()
    }

    func acceptSuggestion(_ suggestion: DictionarySuggestion) {
        add(suggestion.phrase, source: .learned)
        suggestions.removeAll { $0.id == suggestion.id }
        saveSuggestions()
    }

    func dismissSuggestion(_ suggestion: DictionarySuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
        saveSuggestions()
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = try? Data(contentsOf: entriesFileURL) else { return }
        entries = (try? JSONDecoder().decode([DictionaryEntry].self, from: data)) ?? []
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: entriesFileURL, options: .atomic)
    }

    private func loadSuggestions() {
        guard let data = try? Data(contentsOf: suggestionsFileURL) else { return }
        suggestions = (try? JSONDecoder().decode([DictionarySuggestion].self, from: data)) ?? []
    }

    private func saveSuggestions() {
        guard let data = try? JSONEncoder().encode(suggestions) else { return }
        try? data.write(to: suggestionsFileURL, options: .atomic)
    }
}
