# Apple Speech API Reference

Quick reference for the `SpeechAnalyzer` APIs we're building on. All APIs require macOS 26+ / iOS 26+.

## Core classes

### SpeechAnalyzer

The coordinator. Accepts one or more modules, receives audio input, manages the analysis lifecycle.

```swift
import Speech

let transcriber = SpeechTranscriber(
    locale: Locale.current,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],
    attributeOptions: [.audioTimeRange]
)

let analyzer = SpeechAnalyzer(modules: [transcriber])
```

**Key methods:**
- `start(inputSequence:)` — begin streaming analysis from an `AsyncStream<AnalyzerInput>`
- `start(inputAudioFile:finishAfterFile:)` — analyze a file
- `finalizeAndFinishThroughEndOfInput()` — signal that no more audio is coming

**Lifecycle:** once finished, the analyzer stops accepting input and cannot reconfigure modules. Result streams close but previously emitted results remain accessible.

### SpeechTranscriber

The transcription module. Produces text from speech audio.

```swift
let transcriber = SpeechTranscriber(
    locale: Locale(identifier: "en-US"),
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],
    attributeOptions: [.audioTimeRange]
)
```

**Options:**
- `reportingOptions: [.volatileResults]` — emit in-progress partial results (essential for live UI)
- `attributeOptions: [.audioTimeRange]` — include `CMTimeRange` on each result
- `preset: .offlineTranscription` — convenience preset for batch transcription

**Results:**
```swift
for try await result in transcriber.results {
    let text = String(result.text.characters)
    let isFinal = result.isFinal
    // volatile results: isFinal == false, may change
    // final results: isFinal == true, locked in
}
```

Result properties:
- `text` — `AttributedString` with the transcribed content
- `isFinal` — `Bool`, whether this result is finalized
- `audioTimeRange` — `CMTimeRange` (if `.audioTimeRange` attribute requested)

### DictationTranscriber

Alternative to `SpeechTranscriber`. Optimized for natural dictation with punctuation, sentence structure, and conversational formatting. Better for note-taking and long-form text. Supports the same languages as the old `SFSpeechRecognizer` from iOS 10.

Use `DictationTranscriber` when you want formatted, natural prose.
Use `SpeechTranscriber` when you want raw words (commands, search, keywords).

**For Speak:** We should evaluate both. `DictationTranscriber` may produce better output for general dictation since it handles punctuation and structure natively.

### SpeechDetector

Voice activity detection (VAD) only — detects when speech is present without transcribing it. Must be paired with a transcriber module. Useful for UI indicators (show when user is speaking vs silent).

```swift
let detector = SpeechDetector(
    detectionOptions: [],
    reportResults: true
)
```

## Audio input

### AsyncStream approach (live microphone)

```swift
let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()

// Feed audio buffers from AVAudioEngine
audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
    continuation.yield(.audioBuffer(buffer))
}

// Start the analyzer
try await analyzer.start(inputSequence: inputSequence)

// When done recording
continuation.finish()
try await analyzer.finalizeAndFinishThroughEndOfInput()
```

### Buffer format conversion

The audio format from `AVAudioEngine.inputNode` may not match what `SpeechAnalyzer` expects. Use `AVAudioConverter`:

```swift
let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
let targetFormat = /* format expected by SpeechAnalyzer */
let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

// Convert each buffer before yielding to the stream
```

## Model management

### AssetInventory

Language models are managed by the system. Check availability and trigger downloads:

```swift
// Check if locale is supported at all
let supported = await SpeechTranscriber.supportedLocales

// Check if the model is already installed
let installed = await SpeechTranscriber.installedLocales

// Download if needed
if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
    try await downloader.downloadAndInstall()
}
```

**Supported locales (SpeechTranscriber):**
ar_SA, da_DK, de_AT, de_DE, en_AU, en_GB, en_US, es_ES, fr_FR, it_IT, ja_JP, ko_KR, pt_BR, ru_RU, zh_CN — and more being added.

## Permissions

### Speech recognition
```swift
SFSpeechRecognizer.requestAuthorization { status in
    switch status {
    case .authorized: // good to go
    case .denied, .restricted, .notDetermined: // handle
    }
}
```

### Microphone
Declared in `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Speak needs microphone access to transcribe your voice.</string>
```

## Key differences from SFSpeechRecognizer

| Aspect | SFSpeechRecognizer (old) | SpeechAnalyzer (new) |
|--------|--------------------------|----------------------|
| Duration limit | ~1 minute | Unlimited |
| Offline support | Limited | Full, on-device |
| Concurrency model | Callback-based | async/await |
| Configuration | Basic | Modular (attach/detach modules) |
| Model updates | Automatic, opaque | Programmatic via AssetInventory |
| Requires Siri | Yes | No |

## References

- [WWDC 2025 Session 277 — Bring advanced speech-to-text to your app](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple Documentation — SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Apple Documentation — SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Apple Guide — Bringing advanced speech-to-text to your app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app)
- [iOS 26 SpeechAnalyzer Guide (Anton Gubarenko)](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [Implementing advanced speech-to-text in SwiftUI (Create with Swift)](https://www.createwithswift.com/implementing-advanced-speech-to-text-in-your-swiftui-app/)
- [Swift Scribe — open source example](https://github.com/FluidInference/swift-scribe)
