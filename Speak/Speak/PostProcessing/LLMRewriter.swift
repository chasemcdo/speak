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
        - When the speaker dictates a sequence of items (e.g. "first… second… third…", \
        "number one… number two…", "one thing… another thing…"), format as a numbered list
        - When the speaker lists items without explicit ordering (e.g. "we need milk and \
        eggs and bread"), format as a bulleted list using dashes (-)
        - When the speaker dictates multiple distinct thoughts or topics, separate them \
        into paragraphs with blank lines between them
        - When the speaker dictates something that is clearly a single sentence or short \
        thought, keep it as a single line — do NOT force it into a list
        - Match any existing formatting style if surrounding context is provided

        Screen vocabulary rules:
        - When a vocabulary list from the user's screen is provided, use those exact \
        spellings for any names, filenames, identifiers, or terms that sound similar
        - For example, if the vocabulary contains "Daniyal" and the speaker says something \
        that sounds like "Daniel", use "Daniyal"
        - If the vocabulary contains "generate_changelog.sh", use that exact formatting \
        rather than "generate changelog" or "generate_changelog"
        - Only apply vocabulary corrections when the spoken word is a plausible match

        Important:
        - Do NOT add information, opinions, or change the intent
        - Do NOT over-format — short simple dictations should stay as plain sentences
        - Return ONLY the formatted text, nothing else
        """

    func apply(to text: String, context: ProcessingContext) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            return text
        }

        // Build vocabulary hint from screen context
        let vocabularyHint = Self.buildVocabularyHint(from: context.screenVocabulary)

        let prompt: String
        if let surrounding = context.surroundingText, !surrounding.isEmpty {
            prompt = """
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
            prompt = """
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
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Hallucination guard: reject drastically different output.
            // Use a generous upper bound since list formatting adds newlines and markers.
            let ratio = Double(cleaned.count) / Double(text.count)
            if ratio < 0.3 || ratio > 3.0 || cleaned.isEmpty {
                return text
            }

            return cleaned
        }
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
