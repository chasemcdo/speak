# Speak

An open-source, free macOS dictation app that wraps Apple's on-device SpeechAnalyzer API in a polished, Aqua Voice / Wispr Flow-style UX.

## Why

Apple shipped a powerful on-device speech-to-text engine with macOS 26 (`SpeechAnalyzer`), but their built-in dictation UX is minimal. Commercial alternatives like Aqua Voice ($8/mo) and Wispr Flow ($8/mo) charge a subscription and rely on cloud processing.

Speak aims to bridge that gap: **the accuracy of Apple's on-device model, wrapped in a modern dictation UX, 100% free and open source.**

## Core idea

```
[Hotkey] → [Floating overlay] → [SpeechAnalyzer streaming] → [Preview text] → [Paste into active app]
```

- Fully on-device, no network required
- Works in any text field across any app
- Real-time streaming transcription with volatile + final results
- Lightweight native Swift app

## Status

Early planning phase. See [ARCHITECTURE.md](ARCHITECTURE.md) and [ROADMAP.md](ROADMAP.md) for details.

## Requirements

- macOS 26+
- Xcode 26+
- Swift 6.2+
- Microphone permission
- Accessibility permission (for pasting into active text fields)

## License

MIT
