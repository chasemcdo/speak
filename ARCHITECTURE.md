# Architecture

## System overview

Speak is a menu bar app with no main window. The primary interaction is:

1. User presses a global hotkey (e.g. `⌥ Space`)
2. A small floating overlay panel appears near the cursor or active text field
3. Audio capture begins and streams into Apple's `SpeechAnalyzer`
4. Transcribed text renders in real-time inside the overlay (volatile results update live, final results lock in)
5. User presses the hotkey again (or `Return`) to confirm
6. Text is pasted into the previously-focused text field via the system pasteboard + `Cmd+V` keystroke simulation

## Component diagram

```
┌─────────────────────────────────────────────────────┐
│                     Speak App                       │
│                                                     │
│  ┌──────────┐   ┌──────────────┐   ┌────────────┐  │
│  │  Hotkey   │──▶│   Overlay    │──▶│   Paste    │  │
│  │ Listener  │   │   Panel      │   │  Service   │  │
│  └──────────┘   └──────┬───────┘   └────────────┘  │
│                        │                            │
│  ┌──────────┐   ┌──────▼───────┐                    │
│  │  Audio   │──▶│ Transcription│                    │
│  │ Capture  │   │   Engine     │                    │
│  └──────────┘   └──────────────┘                    │
│                                                     │
│  ┌──────────┐                                       │
│  │ Settings │                                       │
│  │  Store   │                                       │
│  └──────────┘                                       │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│ Apple Speech     │
│ Framework        │
│ (SpeechAnalyzer) │
└─────────────────┘
```

## Components

### 1. Hotkey Listener

Registers a system-wide global hotkey using `NSEvent.addGlobalMonitorForEvents` or the `Carbon` `RegisterEventHotKey` API. Toggles the overlay panel on/off.

**Responsibilities:**
- Register/unregister global hotkey
- Remember which app/text field had focus before activation
- Signal overlay to appear/dismiss
- Signal transcription engine to start/stop

### 2. Audio Capture

Captures microphone audio using `AVAudioEngine` and feeds PCM buffers into the transcription engine.

**Responsibilities:**
- Request and verify microphone permission
- Install audio tap on `AVAudioEngine.inputNode`
- Convert buffers to the format expected by `SpeechAnalyzer`
- Yield buffers into an `AsyncStream<AnalyzerInput>`

**Key detail:** The audio format from `AVAudioEngine` may not match what `SpeechAnalyzer` expects. A `BufferConverter` (using `AVAudioConverter`) handles format conversion.

### 3. Transcription Engine

Wraps Apple's `SpeechAnalyzer` + `SpeechTranscriber` APIs. Manages the lifecycle of a transcription session.

**Responsibilities:**
- Initialize `SpeechTranscriber` with locale and options
- Create `SpeechAnalyzer` with the transcriber module attached
- Feed audio via `analyzer.start(inputSequence:)`
- Consume `transcriber.results` async sequence
- Distinguish volatile (in-progress) vs final results
- Emit transcription updates to the overlay via an `@Observable` model
- Handle model availability via `AssetInventory` (download if needed)

**Configuration:**
```swift
SpeechTranscriber(
    locale: Locale.current,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],
    attributeOptions: [.audioTimeRange]
)
```

### 4. Overlay Panel

A floating `NSPanel` (or SwiftUI `Window` with `.panel` style) that displays the live transcription.

**Responsibilities:**
- Appear near the cursor or active text field when triggered
- Display streaming text with visual distinction between volatile and final segments
- Show recording state indicator (waveform or pulsing dot)
- Dismiss on confirm (Return / hotkey) or cancel (Escape)
- Stay above all other windows (`NSWindow.Level.floating`)
- Not steal focus from the previously active app (`.nonactivatingPanel`)

**Design principles:**
- Minimal, non-intrusive — small pill or card shape
- Volatile text shown in lighter color, final text in full color
- No unnecessary chrome — just text and a subtle state indicator

### 5. Paste Service

Handles inserting the transcribed text into the previously-focused text field.

**Responsibilities:**
- Save current pasteboard contents
- Write transcription to pasteboard
- Simulate `Cmd+V` keystroke via `CGEvent`
- Restore original pasteboard contents after a brief delay

**Alternative approach:** Use the Accessibility API (`AXUIElement`) to set the value of the focused text field directly. This avoids clobbering the pasteboard but is less reliable across apps.

### 6. Settings Store

Persists user preferences via `UserDefaults` or a plist.

**Settings (Phase 1):**
- Hotkey binding
- Transcription locale
- Auto-paste vs manual paste toggle

## Data flow

```
Hotkey pressed
    │
    ▼
Remember focused app ──────────────────────────┐
    │                                          │
    ▼                                          │
Show overlay panel                             │
    │                                          │
    ▼                                          │
Start AVAudioEngine                            │
    │                                          │
    ▼                                          │
Audio buffers ──▶ AsyncStream<AnalyzerInput>   │
                      │                        │
                      ▼                        │
              SpeechAnalyzer.start()            │
                      │                        │
                      ▼                        │
              SpeechTranscriber.results         │
                      │                        │
          ┌───────────┴───────────┐            │
          ▼                       ▼            │
    Volatile result          Final result      │
    (update overlay)         (lock in text)    │
                                               │
Hotkey pressed again (confirm)                 │
    │                                          │
    ▼                                          │
Stop audio + finalize analyzer                 │
    │                                          │
    ▼                                          │
Paste text into previously focused app ◀───────┘
    │
    ▼
Dismiss overlay
```

## Technology choices

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| App lifecycle | SwiftUI App + `MenuBarExtra` | Native menu bar presence, minimal boilerplate |
| Overlay UI | SwiftUI in `NSPanel` | Modern declarative UI, easy to iterate |
| Audio capture | `AVAudioEngine` | Low-latency, buffer-level access |
| Transcription | `SpeechAnalyzer` + `SpeechTranscriber` | Apple's on-device model, no cost, great accuracy |
| Global hotkey | `NSEvent.addGlobalMonitorForEvents` | System-wide keyboard monitoring |
| Paste | `NSPasteboard` + `CGEvent` | Universal app compatibility |
| Settings | `@AppStorage` / `UserDefaults` | Simple, built-in persistence |
| State management | `@Observable` (Observation framework) | Modern Swift, no Combine boilerplate |

## Permissions required

| Permission | Why | How |
|-----------|-----|-----|
| Microphone | Audio capture | `AVAudioSession` / `Info.plist` `NSMicrophoneUsageDescription` |
| Accessibility | Global hotkey + paste simulation + (future) context reading | System Settings > Privacy > Accessibility |
| Speech Recognition | `SpeechAnalyzer` usage | `SFSpeechRecognizer.requestAuthorization()` |

## Future considerations (out of scope for Phase 1)

These are documented here for architectural awareness but are **not** part of the initial build:

- **Context awareness** — Read surrounding text via Accessibility API (`AXUIElement`) to improve accuracy
- **Post-processing** — Filler word removal, formatting, style adaptation via local LLM
- **Command mode** — Voice commands like "delete that", "make it a list"
- **Custom dictionary** — User-defined vocabulary for domain-specific terms
- **Multi-language** — Hot-switch between languages mid-dictation
