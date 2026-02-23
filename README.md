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

## Install

### Download (easiest)

1. Grab the latest **Speak.dmg** from [Releases](../../releases)
2. Open the DMG and drag **Speak** to your Applications folder
3. On first launch, right-click the app and choose **Open** (macOS requires this for unsigned apps — you only need to do it once)
4. Grant Microphone and Accessibility permissions when prompted

### Build from source

Requires macOS 26+ and Xcode 26+.

```bash
git clone https://github.com/chasemcdo/speak.git
cd speak
make app       # builds build/Speak.app
make dmg       # packages into build/Speak.dmg (optional)
```

Or with Swift Package Manager for development:

```bash
cd Speak
swift build
```

## Status

Early planning phase. See [ARCHITECTURE.md](ARCHITECTURE.md) and [ROADMAP.md](ROADMAP.md) for details.

## Requirements

- macOS 26+
- Xcode 26+ (build from source only)
- Microphone permission
- Accessibility permission (for pasting into active text fields)

## License

MIT
