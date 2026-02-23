import Foundation

/// Removes common filler words and verbal tics from transcribed text.
struct FillerWordFilter: TextFilter {
    /// Filler patterns ordered from longest to shortest to avoid partial matches.
    /// Each pattern is a regex string that matches the filler at word boundaries.
    private static let fillerPatterns: [(pattern: String, replacement: String)] = [
        // Multi-word fillers (match first to avoid partial removal)
        (#"\b[Ss]o\s+yeah\b[,.]?\s*"#, ""),
        (#"\b[Yy]ou\s+know\b[,.]?\s*"#, ""),
        (#"\b[Ii]\s+mean\b[,.]?\s*"#, ""),
        (#"\b[Ss]ort\s+of\b[,.]?\s*"#, ""),
        (#"\b[Kk]ind\s+of\b[,.]?\s*"#, ""),
        (#"\b[Uu]h\s+huh\b[,.]?\s*"#, ""),

        // "like" only when used as filler — between commas, or at sentence start followed by comma
        (#",\s*like,\s*"#, ", "),
        (#"^[Ll]ike,\s*"#, ""),

        // Single-word fillers
        (#"\b[Uu]mm\b[,.]?\s*"#, ""),
        (#"\b[Uu]hh\b[,.]?\s*"#, ""),
        (#"\b[Uu]m\b[,.]?\s*"#, ""),
        (#"\b[Uu]h\b[,.]?\s*"#, ""),
        (#"\b[Ee]r\b[,.]?\s*"#, ""),
        (#"\b[Aa]h\b[,.]?\s*"#, ""),
        (#"\b[Hh]mm\b[,.]?\s*"#, ""),
        (#"\b[Bb]asically\b[,.]?\s*"#, ""),

        // "actually" and "right" only at sentence start (conservative)
        (#"(?:^|(?<=\.\s))[Aa]ctually,?\s*"#, ""),
        (#"(?:^|(?<=\.\s))[Rr]ight,\s*"#, ""),

        // "so" only at the very start of the text when followed by comma
        (#"^[Ss]o,\s*"#, ""),
    ]

    func apply(to text: String, context: ProcessingContext) async throws -> String {
        var result = text

        for (pattern, replacement) in Self.fillerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }

        // Clean up artifacts: collapse multiple spaces, trim
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)

        // Fix orphaned punctuation from removal (e.g. ", , " → ", ")
        result = result.replacingOccurrences(of: ",\\s*,", with: ",", options: .regularExpression)

        // Ensure first character is still capitalized after removals
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        return result
    }
}
