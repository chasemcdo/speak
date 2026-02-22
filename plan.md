# Phase 1 Implementation Plan — Core Transcription Layer

## Goal

Build a working macOS menu bar app that lets a user press a hotkey, dictate via microphone, see live transcription in a floating overlay, and paste the result into whatever app they were using. No post-processing, no commands, no LLM — just the core loop.

## Project structure

```
Speak/
├── Speak.xcodeproj
├── Speak/
│   ├── SpeakApp.swift              # @main, MenuBarExtra, app lifecycle
│   ├── Info.plist                   # Permission descriptions
│   ├── Assets.xcassets              # App icon (microphone glyph)
│   │
│   ├── Audio/
│   │   └── AudioCaptureManager.swift   # AVAudioEngine, mic permission, buffer streaming
│   │
│   ├── Transcription/
│   │   ├── TranscriptionEngine.swift   # SpeechAnalyzer + SpeechTranscriber wrapper
│   │   └── ModelManager.swift          # AssetInventory locale/model checks + download
│   │
│   ├── Overlay/
│   │   ├── OverlayPanel.swift          # NSPanel subclass (non-activating, floating)
│   │   └── OverlayView.swift           # SwiftUI view for live transcription display
│   │
│   ├── Input/
│   │   ├── HotkeyManager.swift         # Global hotkey registration + handling
│   │   └── PasteService.swift          # NSPasteboard write + CGEvent Cmd+V simulation
│   │
│   ├── Settings/
│   │   └── SettingsView.swift          # Language picker, hotkey config, auto-paste toggle
│   │
│   └── Models/
│       └── AppState.swift              # @Observable shared state (recording, text, errors)
│
├── README.md
├── ARCHITECTURE.md
├── ROADMAP.md
└── docs/
    └── APPLE_SPEECH_API.md
```

## Implementation steps

Steps are ordered by dependency — each builds on the previous.

### Step 1: Xcode project scaffold

Create the Xcode project and establish the menu bar app shell.

**Files:** `SpeakApp.swift`, `Info.plist`, `Assets.xcassets`

**What to build:**
- New Xcode project: macOS App, SwiftUI lifecycle, deployment target macOS 26
- `SpeakApp.swift`: Use `MenuBarExtra` with a system microphone icon (`systemName: "mic.fill"`)
- Menu contents: "Quit Speak" button, "Settings..." placeholder
- `Info.plist` entries:
  - `NSMicrophoneUsageDescription`: "Speak needs microphone access to transcribe your voice."
  - `NSSpeechRecognitionUsageDescription`: "Speak uses on-device speech recognition to transcribe your voice."
- Set `LSUIElement = true` so the app has no dock icon (menu bar only)
- Add a placeholder app icon to `Assets.xcassets`

**Verify:** App launches, appears in the menu bar, Quit works.

### Step 2: Shared app state

Create the observable state model that all components share.

**Files:** `AppState.swift`

**What to build:**
```swift
@Observable
final class AppState {
    var isRecording = false
    var finalizedText = ""        // Locked-in transcription segments
    var volatileText = ""         // In-progress segment (may change)
    var error: String?            // User-facing error message

    var displayText: String {
        finalizedText + volatileText
    }

    func reset() {
        isRecording = false
        finalizedText = ""
        volatileText = ""
        error = nil
    }
}
```

Inject into the SwiftUI environment from `SpeakApp.swift` via `@State private var appState = AppState()`.

### Step 3: Audio capture

Implement microphone capture that produces an async stream of audio buffers.

**Files:** `AudioCaptureManager.swift`

**What to build:**
- Class `AudioCaptureManager` with `AVAudioEngine`
- `requestPermission() async -> Bool` — request mic access
- `startCapture() -> AsyncStream<AVAudioPCMBuffer>` — install tap on `inputNode`, yield buffers
- `stopCapture()` — remove tap, stop engine
- Handle format negotiation: query `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` for the target format, use `AVAudioConverter` if the input node's native format doesn't match
- Buffer size: 4096 frames (good balance of latency vs overhead, matches Swift Scribe's approach)

**Key considerations:**
- `AVAudioEngine.inputNode.outputFormat(forBus: 0)` gives the hardware's native format
- The converter must be created once and reused (not per-buffer)
- The `AsyncStream` continuation should use `.bufferingPolicy(.bufferingNewest(10))` to avoid unbounded growth if the consumer is slow

**Verify:** Can start/stop audio capture without crashes, buffers flow through the stream.

### Step 4: Transcription engine

Wrap SpeechAnalyzer to consume audio buffers and produce transcription results.

**Files:** `TranscriptionEngine.swift`, `ModelManager.swift`

**`ModelManager`:**
- `ensureModelAvailable(for locale: Locale) async throws` — check `SpeechTranscriber.supportedLocales`, check `SpeechTranscriber.installedLocales`, download via `AssetInventory` if needed
- Surface download progress if possible for UI feedback

**`TranscriptionEngine`:**
- Takes a reference to `AppState` and `AudioCaptureManager`
- `startSession() async throws`:
  1. Ensure model is available via `ModelManager`
  2. Create `SpeechTranscriber` with locale, `.volatileResults` reporting, `.audioTimeRange` attributes
  3. Create `SpeechAnalyzer(modules: [transcriber])`
  4. Start audio capture, get the `AsyncStream<AVAudioPCMBuffer>`
  5. Create `AsyncStream<AnalyzerInput>` — map each PCM buffer through the converter, yield as `AnalyzerInput`
  6. Call `analyzer.start(inputSequence:)`
  7. Spawn a `Task` to iterate `transcriber.results`:
     - If `result.isFinal`: append `String(result.text.characters)` to `appState.finalizedText`, clear `appState.volatileText`
     - If not final (volatile): set `appState.volatileText = String(result.text.characters)`
- `stopSession() async`:
  1. Stop audio capture (finish the continuation)
  2. Call `analyzer.finalizeAndFinishThroughEndOfInput()`
  3. Wait for remaining results to flush
  4. Set `appState.isRecording = false`

**Open question — SpeechTranscriber vs DictationTranscriber:**
`DictationTranscriber` adds punctuation and sentence structure automatically, which is probably what users want for general dictation. `SpeechTranscriber` gives raw words. We should start with `DictationTranscriber` for better out-of-the-box prose quality, but make it easy to swap (both conform to the same module pattern). If `DictationTranscriber` has issues (latency, availability), fall back to `SpeechTranscriber`.

**Verify:** Can start a session, speak, see `appState.finalizedText` and `volatileText` update correctly in the debugger or a test view.

### Step 5: Floating overlay

Build the non-activating floating panel that shows live transcription.

**Files:** `OverlayPanel.swift`, `OverlayView.swift`

**`OverlayPanel` (NSPanel subclass):**
```swift
class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }
}
```

Key behaviors:
- `.nonactivatingPanel` — does NOT steal focus from the app the user is typing in
- `.floating` level — stays above other windows
- Borderless with a custom SwiftUI view for the content
- Position: center horizontally on screen, near bottom (above the dock) — simple and predictable. Future improvement could position near the cursor.

**`OverlayView` (SwiftUI):**
- Rounded rectangle card with slight blur/transparency (`.ultraThinMaterial`)
- Left side: pulsing red dot when recording
- Main area: text display
  - `appState.finalizedText` in primary color, normal weight
  - `appState.volatileText` in secondary color, lighter weight (visually distinct as "in progress")
- If `appState.displayText` is empty, show placeholder: "Listening..."
- Fixed max width (~400pt), height grows with content up to a max (~200pt), then scrolls
- Subtle corner radius, no title bar, no close button

**Verify:** Panel appears/disappears without stealing focus, text updates live, looks clean.

### Step 6: Global hotkey + orchestration

Wire the hotkey to toggle the full dictation flow.

**Files:** `HotkeyManager.swift`, updates to `SpeakApp.swift`

**`HotkeyManager`:**
- Register a global hotkey (default `⌥ Space`) using `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`
- Also register `NSEvent.addLocalMonitorForEvents` so the hotkey works when Speak itself is focused
- On hotkey press, call a provided closure (the toggle action)
- Store the hotkey combo in `UserDefaults` so it can be changed later

**Orchestration (in `SpeakApp.swift` or a dedicated `AppCoordinator`):**

Toggle flow:
1. **First press (start):**
   - Record which app is frontmost via `NSWorkspace.shared.frontmostApplication`
   - Set `appState.isRecording = true`, reset text
   - Show the overlay panel
   - Start the transcription session
2. **Second press (confirm):**
   - Stop the transcription session
   - Get `appState.displayText`
   - Hide the overlay panel
   - Paste into the previously focused app (Step 7)
   - Reset state
3. **Escape (cancel):**
   - Stop the transcription session
   - Hide the overlay panel
   - Reset state, discard text

Register for Escape key in the overlay panel's key handling.

**Verify:** Hotkey toggles the full flow. First press starts recording + shows overlay. Second press stops + hides. Escape cancels.

### Step 7: Paste service

Insert the transcribed text into the previously focused app.

**Files:** `PasteService.swift`

**What to build:**
```swift
struct PasteService {
    static func paste(_ text: String, into app: NSRunningApplication?) {
        // 1. Save current pasteboard
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.pasteboardItems?.compactMap { /* save */ }

        // 2. Write transcription to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Activate the target app
        app?.activate()

        // 4. Brief delay for app activation
        // Then simulate Cmd+V
        let source = CGEventSource(stateID: .hidEventState)
        let keyDown = CGEvent(keyboardEventType: .keyDown, virtualKey: 0x09, keyIsDown: true) // 'v'
        let keyUp = CGEvent(keyboardEventType: .keyUp, virtualKey: 0x09, keyIsDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // 5. After a delay, restore original pasteboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // restore previousContents
        }
    }
}
```

**Key considerations:**
- Need a small delay (~100ms) between `app?.activate()` and the Cmd+V keystroke to ensure the target app is actually frontmost
- Restoring the pasteboard should happen after another delay (~500ms) to ensure the paste completes
- This requires Accessibility permission — the app should check `AXIsProcessTrusted()` on launch and guide the user to grant it if not

**Verify:** After dictation, text appears in the previously focused text field (test with TextEdit, Notes, a browser input, Slack).

### Step 8: Settings view

Basic settings window.

**Files:** `SettingsView.swift`, updates to `SpeakApp.swift`

**What to build:**
- SwiftUI `Settings` scene (macOS native settings window)
- Language picker: dropdown populated from `SpeechTranscriber.supportedLocales`, stored in `@AppStorage("locale")`
- Auto-paste toggle: `@AppStorage("autoPaste")` — when off, text is just copied to clipboard on confirm, not pasted
- Launch at login: use `SMAppService.mainApp` to register/unregister
- Hotkey display (read-only for v0.1, custom binding is a future enhancement)

**Verify:** Settings persist across app restarts, language change affects transcription.

### Step 9: Permission onboarding

Guide users through granting required permissions on first launch.

**Updates to:** `SpeakApp.swift`, possibly a new `OnboardingView.swift`

**What to build:**
- On first launch, check:
  1. Microphone: `AVCaptureDevice.authorizationStatus(for: .audio)`
  2. Accessibility: `AXIsProcessTrusted()`
  3. Speech: `SFSpeechRecognizer.authorizationStatus()`
- If any are missing, show a simple window explaining what's needed and why
- Provide buttons that open the relevant System Settings panes
- Store `@AppStorage("onboardingComplete")` to skip on subsequent launches

**Verify:** Fresh install walks through permissions correctly. App works after all are granted.

## What's explicitly NOT in this plan

- Post-processing (filler removal, formatting, rewriting) — Phase 2
- Voice commands ("delete that", "new paragraph") — Phase 3
- Context awareness (reading surrounding text) — Phase 2
- Custom dictionary — Phase 3
- Multi-language hot-switching — Phase 3
- iOS/iPadOS support — non-goal

## Open decisions

1. **SpeechTranscriber vs DictationTranscriber** — Start with `DictationTranscriber` for better punctuation/formatting, but keep the code flexible to swap. Need to test both on actual hardware.

2. **Overlay positioning** — Start with fixed bottom-center. Moving to cursor-relative positioning is a polish item but adds complexity (need to track cursor position across apps).

3. **Hotkey mechanism** — `NSEvent.addGlobalMonitorForEvents` is simplest but has limitations (doesn't fire if another app has a conflicting hotkey). `Carbon RegisterEventHotKey` is more robust but older API. Start with `NSEvent`, switch if needed.

4. **Pasteboard restoration** — Saving/restoring the full pasteboard (which can contain images, files, rich text) is non-trivial. For v0.1, we could skip restoration and just overwrite. Users of clipboard managers won't mind. Decide based on testing.

## Reference

- [ARCHITECTURE.md](ARCHITECTURE.md) — component design and data flow
- [ROADMAP.md](ROADMAP.md) — milestone checklist
- [docs/APPLE_SPEECH_API.md](docs/APPLE_SPEECH_API.md) — SpeechAnalyzer API reference
- [Swift Scribe](https://github.com/FluidInference/swift-scribe) — reference implementation for SpeechAnalyzer + AVAudioEngine wiring
