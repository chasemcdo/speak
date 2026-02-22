import AVFoundation
import Speech

@Observable
final class TranscriptionEngine {
    private let audioCapture = AudioCaptureManager()
    private let modelManager = ModelManager()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var resultsTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    private(set) var isRunning = false

    // MARK: - Session lifecycle

    /// Start a transcription session. Streams results into the provided AppState.
    func startSession(appState: AppState, locale: Locale) async throws {
        guard !isRunning else { return }

        // 1. Set up the transcriber module
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        // 2. Ensure model is downloaded
        appState.isModelDownloading = true
        do {
            try await modelManager.ensureModelAvailable(for: transcriber)
        } catch {
            appState.isModelDownloading = false
            throw TranscriptionError.modelUnavailable(locale: locale)
        }
        appState.isModelDownloading = false

        // 3. Prepare audio format
        try await audioCapture.prepareFormat(compatibleWith: transcriber)

        // 4. Create the analyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // 5. Start audio capture
        let audioStream = try audioCapture.startCapture()

        // 6. Create the AnalyzerInput stream, bridging audio buffers
        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        // Feed audio buffers into the analyzer input stream
        Task {
            for await buffer in audioStream {
                inputContinuation.yield(.audioBuffer(buffer))
            }
            inputContinuation.finish()
        }

        // 7. Start the analyzer
        try await analyzer.start(inputSequence: inputSequence)

        // 8. Consume results
        resultsTask = Task { @MainActor in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        appState.appendFinalizedText(text)
                    } else {
                        appState.updateVolatileText(text)
                    }
                }
            } catch {
                appState.error = "Transcription error: \(error.localizedDescription)"
            }
        }

        isRunning = true
        appState.isRecording = true
    }

    /// Stop the current transcription session and finalize remaining results.
    func stopSession() async {
        guard isRunning else { return }

        // Stop audio capture first
        audioCapture.stopCapture()

        // Finalize the analyzer — this flushes remaining results
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()

        // Wait briefly for final results to arrive
        try? await Task.sleep(for: .milliseconds(200))

        // Clean up
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        inputContinuation = nil
        isRunning = false
    }
}

enum TranscriptionError: LocalizedError {
    case modelUnavailable(locale: Locale)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let locale):
            return "Speech model for \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier) is not available."
        case .notAuthorized:
            return "Speech recognition is not authorized."
        }
    }
}
