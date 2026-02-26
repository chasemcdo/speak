# Speak

![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS_26%2B-blue)
![License: GPLv3](https://img.shields.io/badge/license-GPLv3-green)
![Built with: Swift](https://img.shields.io/badge/built_with-Swift-orange)

> Speak is a 100% local, native macOS dictation app built on Apple's SpeechAnalyzer and FoundationModels. Hold a hotkey, dictate, release — your text lands in whatever app you're working in. Free, open source, no cloud.

## Why

Apple shipped a powerful on-device speech-to-text engine with macOS 26 — **SpeechAnalyzer** — but their built-in dictation UX is minimal. On top of that, **FoundationModels** enables on-device LLM-powered text cleanup without any cloud dependency. Commercial alternatives like Aqua Voice ($8/mo) and Wispr Flow ($8/mo) charge a subscription and rely on cloud processing.

Speak aims to bridge that gap: **the accuracy of Apple's SpeechAnalyzer for transcription and FoundationModels for intelligent text cleanup, wrapped in a modern dictation UX, 100% free and open source.**

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
make tidy      # formats and lints source code
```

Or with Swift Package Manager for development:

```bash
cd Speak
swift build
```

## Website

A simple Next.js landing/docs site lives in [`site`](site).

```bash
cd site
pnpm install
pnpm dev
```

Build for production:

```bash
cd site
pnpm build
```

## Status

Active development. See [ARCHITECTURE.md](ARCHITECTURE.md) and [ROADMAP.md](ROADMAP.md) for details.

<!-- GitHub Topics: Consider adding these via the GitHub UI for discoverability:
     macos, swift, swiftui, dictation, speech-recognition, on-device-ai, apple-speechanalyzer, open-source -->

## Requirements

- macOS 26+
- Xcode 26+ (build from source only)
- Microphone permission
- Accessibility permission (for pasting into active text fields)

## License

GNU General Public License v3 (GPLv3)
