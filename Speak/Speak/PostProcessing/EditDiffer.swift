import Foundation

struct WordReplacement {
    let original: String
    let replacement: String
}

enum EditDiffer {
    static func findReplacements(original: String, edited: String) -> [WordReplacement] {
        let originalWords = tokenize(original)
        let editedWords = tokenize(edited)

        // If overall similarity is too low, it's a rewrite — not corrections
        if originalWords.isEmpty || editedWords.isEmpty { return [] }
        let diff = editedWords.difference(from: originalWords)
        let changeCount = diff.count
        let totalWords = max(originalWords.count, editedWords.count)
        if changeCount > totalWords { return [] }

        let (removals, insertions) = collectChanges(from: diff)
        return pairReplacements(removals: removals, insertions: insertions)
    }

    // MARK: - Private

    private static func collectChanges(
        from diff: CollectionDifference<String>
    ) -> (removals: [(offset: Int, element: String)], insertions: [(offset: Int, element: String)]) {
        var removals: [(offset: Int, element: String)] = []
        var insertions: [(offset: Int, element: String)] = []

        for change in diff {
            switch change {
            case let .remove(offset, element, _):
                removals.append((offset, element))
            case let .insert(offset, element, _):
                insertions.append((offset, element))
            }
        }
        return (removals, insertions)
    }

    private static func pairReplacements(
        removals: [(offset: Int, element: String)],
        insertions: [(offset: Int, element: String)]
    ) -> [WordReplacement] {
        var replacements: [WordReplacement] = []
        var usedInsertions: Set<Int> = []

        for removal in removals {
            guard let (matchIndex, insertion) = closestInsertion(
                to: removal, in: insertions, excluding: usedInsertions
            ) else { continue }

            let orig = removal.element
            let repl = insertion.element

            if isNoise(original: orig, replacement: repl) { continue }
            usedInsertions.insert(matchIndex)
            replacements.append(WordReplacement(original: orig, replacement: repl))
        }

        return replacements
    }

    private static func closestInsertion(
        to removal: (offset: Int, element: String),
        in insertions: [(offset: Int, element: String)],
        excluding used: Set<Int>
    ) -> (index: Int, insertion: (offset: Int, element: String))? {
        var bestIndex: Int?
        var bestDistance = Int.max

        for (idx, insertion) in insertions.enumerated() where !used.contains(idx) {
            let dist = abs(insertion.offset - removal.offset)
            if dist < bestDistance {
                bestDistance = dist
                bestIndex = idx
            }
        }

        guard let index = bestIndex, bestDistance <= 2 else { return nil }
        return (index, insertions[index])
    }

    private static func isNoise(original: String, replacement: String) -> Bool {
        isCapitalizationOnly(original, replacement)
            || isPunctuationOnly(original, replacement)
            || replacement.count < 3
            || !isSimilar(original, replacement)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    private static func isCapitalizationOnly(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() == rhs.lowercased()
    }

    private static func isPunctuationOnly(_ lhs: String, _ rhs: String) -> Bool {
        let strippedA = lhs.filter { !$0.isPunctuation }
        let strippedB = rhs.filter { !$0.isPunctuation }
        return strippedA == strippedB
    }

    private static func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        StringSimilarity.isSimilar(lhs, rhs)
    }
}
