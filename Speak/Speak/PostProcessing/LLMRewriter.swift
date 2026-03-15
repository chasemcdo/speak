import Foundation
import FoundationModels

/// Uses Apple's on-device FoundationModels (~3B parameter LLM) to intelligently
/// rewrite transcribed speech: filler removal, grammar, punctuation, structural
/// formatting (lists, paragraphs), and style matching to surrounding context.
struct LLMRewriter: TextFilter {
    /// Maximum time to wait for the LLM before falling back to the unprocessed text.
    private static let timeoutSeconds: TimeInterval = 5.0

    private static let systemPrompt = """
    You are a dictation formatting assistant. Transform raw transcribed speech \
    into polished, well-structured written text.

    Cleanup rules:
    - Remove filler words (um, uh, like, you know, basically, sort of, kind of)
    - Fix grammar, spelling, and punctuation
    - Keep the meaning, tone, and intent identical to the original

    Structural formatting rules:
    - Default to plain prose. Most dictated text should remain as sentences and \
    paragraphs — do NOT convert to a list unless the speaker is unmistakably \
    dictating a standalone list of items
    - Only format as a numbered list when the speaker is clearly dictating a \
    freestanding list AND each item is a self-contained entry (e.g. a to-do list, \
    a set of steps, or an enumerated checklist). Mere references to items within a \
    sentence (e.g. "the transfers are number one X number two Y") should stay as prose
    - Only format as a bulleted list using dashes (-) when the speaker lists three or \
    more parallel, independent items that read unnaturally as a run-on sentence
    - When the speaker dictates multiple distinct thoughts or topics, separate them \
    into paragraphs with blank lines between them
    - When in doubt between a list and prose, choose prose
    - Match any existing formatting style if surrounding context is provided

    Voice command rules:
    - The speaker may use inline editing commands during dictation. Interpret these \
    as instructions applied to the surrounding dictated text and do NOT include the \
    command phrase itself in the output
    - "delete that" or "scratch that" = remove the preceding sentence or phrase the \
    speaker is referring to
    - "new paragraph" = start a new paragraph at that point
    - "new line" = insert a single line break at that point
    - "capitalize that" or "cap that" = capitalize the preceding word or phrase
    - "undo last sentence" = remove the last sentence
    - If the speaker says "literally" before a command phrase (e.g. "literally delete \
    that"), treat it as dictated text and keep the words after "literally" in the output

    Screen vocabulary rules:
    - When a vocabulary list from the user's screen is provided, use those exact \
    spellings for any names, filenames, identifiers, or terms that sound similar
    - For example, if the vocabulary contains "Daniyal" and the speaker says something \
    that sounds like "Daniel", use "Daniyal"
    - If the vocabulary contains "generate_changelog.sh", use that exact formatting \
    rather than "generate changelog" or "generate_changelog"
    - Only apply vocabulary corrections when the spoken word is a plausible match

    CRITICAL output rules:
    - Do NOT add information, opinions, or change the intent
    - Do NOT over-format — short simple dictations should stay as plain sentences
    - Do NOT include any preamble, explanation, or commentary
    - Do NOT wrap the output in quotes
    - Respond with ONLY the formatted text — nothing before it, nothing after it
    """

    func apply(to text: String, context: ProcessingContext) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            return text
        }

        // Build vocabulary hint from screen context
        let vocabularyHint = Self.buildVocabularyHint(from: context.screenVocabulary)

        let prompt = if let surrounding = context.surroundingText, !surrounding.isEmpty {
            """
            The user is writing in this context:
            ---
            \(surrounding)
            ---
            \(vocabularyHint)
            Format this dictated text to match the style above. \
            Return ONLY the formatted text:

            \(text)
            """
        } else {
            """
            \(vocabularyHint)
            Format this dictated text for written communication. \
            Return ONLY the formatted text:

            \(text)
            """
        }

        return await withTaskTimeout(seconds: Self.timeoutSeconds, fallback: text) {
            let session = LanguageModelSession {
                Self.systemPrompt
            }

            let response = try await session.respond(to: prompt)
            let cleaned = Self.stripPreamble(
                response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            // Hallucination guard: reject drastically different output.
            // Use a generous upper bound since list formatting adds newlines and markers.
            // The lower bound is relaxed to 0.1 because voice commands like "delete that"
            // can legitimately reduce output significantly.
            if cleaned.isEmpty {
                return text
            }
            let ratio = Double(cleaned.count) / Double(text.count)
            if ratio < 0.1 || ratio > 3.0 {
                return text
            }

            return cleaned
        }
    }

    // MARK: - Preamble stripping

    /// Strip conversational preamble and surrounding quotes that small models sometimes add
    /// despite being told to return only the formatted text.
    private static func stripPreamble(_ text: String) -> String {
        var result = text

        // Remove common preamble patterns (case-insensitive).
        // These match lines like "Sure! Here is the formatted transcript:"
        // or "Here's the formatted text:" followed by the actual content.
        let preamblePatterns: [NSRegularExpression] = (try? [
            NSRegularExpression(
                pattern: #"^(?:sure[!.]?\s*)?here(?:'s| is) the .+?:\s*"#,
                options: [.caseInsensitive]
            ),
        ]) ?? []

        for pattern in preamblePatterns {
            let range = NSRange(result.startIndex..., in: result)
            if let match = pattern.firstMatch(in: result, range: range) {
                let matchRange = Range(match.range, in: result)!
                result = String(result[matchRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip surrounding quotes (e.g. "Hello world" → Hello world).
        if result.count >= 2,
           (result.hasPrefix("\"") && result.hasSuffix("\""))
            || (result.hasPrefix("\u{201C}") && result.hasSuffix("\u{201D}"))
        {
            result = String(result.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    // MARK: - Screen vocabulary

    /// Build a compact vocabulary hint string from screen context.
    /// Returns an empty string if there's nothing useful.
    private static func buildVocabularyHint(from vocab: ScreenVocabulary?) -> String {
        guard let vocab, !vocab.isEmpty else { return "" }

        var terms: [String] = []

        if let title = vocab.windowTitle {
            terms.append("Window: \(title)")
        }

        if let doc = vocab.documentPath {
            // Extract just the filename from a full path
            let filename = (doc as NSString).lastPathComponent
            if !filename.isEmpty {
                terms.append("File: \(filename)")
            }
        }

        // Add visible terms (tab titles, labels, headers)
        for term in vocab.visibleTerms.prefix(15) {
            terms.append(term)
        }

        guard !terms.isEmpty else { return "" }

        let joined = terms.joined(separator: "\n- ")
        return """

        Screen vocabulary (use these exact spellings for matching names/terms):
        - \(joined)

        """
    }

    /// Check whether the on-device model is available for use.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Prewarm the model to reduce first-response latency.
    static func prewarm() async {
        guard isAvailable else { return }
        let session = LanguageModelSession()
        session.prewarm()
    }
}

// MARK: - Timeout helper

/// Run an async operation with a timeout, returning a fallback value if it takes too long.
private func withTaskTimeout<T: Sendable>(
    seconds: TimeInterval,
    fallback: T,
    operation: @escaping @Sendable () async throws -> T
) async -> T {
    await withTaskGroup(of: T.self) { group in
        group.addTask {
            do {
                return try await operation()
            } catch {
                return fallback
            }
        }

        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return fallback
        }

        // Return whichever finishes first
        let result = await group.next() ?? fallback
        group.cancelAll()
        return result
    }
}
