import Foundation

/// Applies basic text formatting: capitalization, smart punctuation, whitespace cleanup.
struct FormattingFilter: TextFilter {
    func apply(to text: String, context: ProcessingContext) async throws -> String {
        var result = text

        result = capitalizeSentenceStarts(result)
        result = applySmartPunctuation(result)
        result = cleanupWhitespace(result)

        return result
    }

    /// Capitalize the first letter after sentence-ending punctuation (.!?)
    private func capitalizeSentenceStarts(_ text: String) -> String {
        // Match: sentence-ending punctuation followed by space(s) and a lowercase letter
        guard let regex = try? NSRegularExpression(pattern: #"([.!?])\s+([a-z])"#) else {
            return text
        }

        var result = text
        let range = NSRange(result.startIndex..., in: result)

        // Process matches in reverse to preserve indices
        let matches = regex.matches(in: result, range: range)
        for match in matches.reversed() {
            guard let letterRange = Range(match.range(at: 2), in: result) else { continue }
            let uppercased = result[letterRange].uppercased()
            result.replaceSubrange(letterRange, with: uppercased)
        }

        // Capitalize the very first character
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        return result
    }

    /// Convert straight quotes to curly, double hyphens to em dashes, triple dots to ellipsis.
    private func applySmartPunctuation(_ text: String) -> String {
        var result = text

        // Triple dots → ellipsis
        result = result.replacingOccurrences(of: "...", with: "\u{2026}")

        // Double hyphens → em dash
        result = result.replacingOccurrences(of: "--", with: "\u{2014}")

        return result
    }

    /// Collapse multiple spaces, trim leading/trailing whitespace.
    private func cleanupWhitespace(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)
        return result
    }
}
