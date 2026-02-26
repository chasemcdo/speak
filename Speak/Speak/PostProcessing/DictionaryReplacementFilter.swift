import Foundation
import NaturalLanguage

struct DictionaryReplacementFilter: TextFilter {
    let phrases: [String]

    func apply(to text: String, context: ProcessingContext) async throws -> String {
        guard !text.isEmpty, !phrases.isEmpty else { return text }

        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text

        var nounRanges: [(range: Range<String.Index>, word: String)] = []
        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameTypeOrLexicalClass
        ) { tag, range in
            if tag == .noun || tag == .personalName || tag == .placeName || tag == .organizationName {
                nounRanges.append((range: range, word: String(text[range])))
            }
            return true
        }

        var result = text
        for (range, word) in nounRanges.reversed() {
            if let match = bestMatch(for: word, in: phrases) {
                result.replaceSubrange(range, with: match)
            }
        }
        return result
    }

    private func bestMatch(for word: String, in phrases: [String]) -> String? {
        guard word.count >= 3 else { return nil }
        var best: (phrase: String, similarity: Double)?
        for phrase in phrases {
            if word.lowercased() == phrase.lowercased() { return nil }
            let sim = StringSimilarity.similarity(word, phrase)
            if sim >= 0.5, sim > (best?.similarity ?? 0) {
                best = (phrase, sim)
            }
        }
        return best?.phrase
    }
}
