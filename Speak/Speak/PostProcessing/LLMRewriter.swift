import Foundation
import FoundationModels

/// Uses Apple's on-device FoundationModels (~3B parameter LLM) to intelligently
/// clean up transcribed speech: filler removal, grammar, punctuation, style matching.
struct LLMRewriter: TextFilter {
    /// Maximum time to wait for the LLM before falling back to the unprocessed text.
    private static let timeoutSeconds: TimeInterval = 3.0

    func apply(to text: String, context: ProcessingContext) async throws -> String {
        // Check model availability — skip silently if not available
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            return text
        }

        // Build the prompt with optional surrounding context
        let prompt: String
        if let surrounding = context.surroundingText, !surrounding.isEmpty {
            prompt = """
            The user is writing in this context:
            ---
            \(surrounding)
            ---

            Clean up this dictated text to match the style and tone above. \
            Return ONLY the cleaned text:

            \(text)
            """
        } else {
            prompt = """
            Clean up this dictated text for written communication. \
            Return ONLY the cleaned text:

            \(text)
            """
        }

        // Run with a timeout to avoid blocking the paste flow
        return await withTaskTimeout(seconds: Self.timeoutSeconds, fallback: text) {
            let session = LanguageModelSession {
                """
                You are a text cleanup assistant for a dictation app. \
                Take raw transcribed speech and clean it up for written use.

                Rules:
                - Remove any remaining filler words (um, uh, like, you know)
                - Fix grammar and punctuation
                - Keep the meaning and tone identical to the original
                - Do NOT add information, opinions, or change the intent
                - Do NOT make the text more formal unless the context suggests it
                - Return ONLY the cleaned text, nothing else
                """
            }

            let response = try await session.respond(to: prompt)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Hallucination guard: reject if the output length is drastically different
            let ratio = Double(cleaned.count) / Double(text.count)
            if ratio < 0.3 || ratio > 2.0 || cleaned.isEmpty {
                return text
            }

            return cleaned
        }
    }

    /// Check whether the on-device model is available for use.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Prewarm the model to reduce first-response latency.
    static func prewarm() async {
        guard isAvailable else { return }
        do {
            let session = LanguageModelSession()
            try await session.prewarm()
        } catch {
            // Prewarm is best-effort
        }
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
