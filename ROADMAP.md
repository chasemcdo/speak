# Roadmap

## Phase 1 — Core transcription layer

**Goal:** A working menu bar app that captures audio, transcribes via SpeechAnalyzer, and pastes text into any app.

### Milestone 1.1: Project scaffold
- [ ] Create Xcode project (SwiftUI App, macOS 26 deployment target)
- [ ] Configure `Info.plist` with required permission descriptions (microphone, speech recognition)
- [ ] Set up `MenuBarExtra` as the app's primary interface
- [ ] Add app icon and basic menu (Quit, Settings placeholder)

### Milestone 1.2: Audio capture
- [ ] Implement `AudioCaptureManager` using `AVAudioEngine`
- [ ] Request and handle microphone permission
- [ ] Install tap on input node, capture PCM buffers
- [ ] Implement `BufferConverter` for format conversion to `SpeechAnalyzer`'s expected format
- [ ] Expose audio as `AsyncStream<AnalyzerInput>`

### Milestone 1.3: Transcription engine
- [ ] Implement `TranscriptionEngine` wrapping `SpeechAnalyzer` + `SpeechTranscriber`
- [ ] Handle model availability check and download via `AssetInventory`
- [ ] Start/stop transcription sessions
- [ ] Consume `transcriber.results` and distinguish volatile vs final results
- [ ] Expose results via `@Observable` model for SwiftUI binding
- [ ] Handle errors gracefully (model not available, permission denied, etc.)

### Milestone 1.4: Floating overlay
- [ ] Create `NSPanel`-based floating overlay (non-activating, always-on-top)
- [ ] Display streaming transcription text (volatile in lighter style, final in bold)
- [ ] Show recording state indicator (pulsing dot or waveform)
- [ ] Position overlay near cursor or near the active text field
- [ ] Dismiss on Escape (cancel) or Return (confirm)

### Milestone 1.5: Global hotkey + paste
- [ ] Register global hotkey (default: `⌥ Space`) via `NSEvent.addGlobalMonitorForEvents`
- [ ] Track which app had focus before hotkey was pressed
- [ ] Implement paste service: write to `NSPasteboard`, simulate `Cmd+V` via `CGEvent`
- [ ] Restore original pasteboard contents after paste
- [ ] Wire everything together: hotkey → overlay → capture → transcribe → paste

### Milestone 1.6: Settings
- [ ] Settings window with hotkey configuration
- [ ] Locale/language picker (from `SpeechTranscriber.supportedLocales`)
- [ ] Auto-paste toggle (paste immediately on confirm vs copy to clipboard only)
- [ ] Launch at login toggle

### Milestone 1.7: Polish + release
- [ ] Handle edge cases (no microphone, model download in progress, accessibility not granted)
- [ ] First-run onboarding flow for permissions
- [ ] README with installation instructions
- [ ] Build and notarize for distribution outside App Store
- [ ] Tag v0.1.0

---

## Phase 2 — Post-processing (future)

**Goal:** Clean up and improve transcribed text before pasting, using local processing.

### 2.1: Filler word removal
- [ ] Strip common filler words/phrases ("um", "uh", "like", "you know", "I mean")
- [ ] Make this configurable (on/off, custom filler list)

### 2.2: Basic formatting
- [ ] Auto-capitalize sentence starts
- [ ] Smart punctuation (convert straight quotes, dashes)
- [ ] Paragraph detection from pauses

### 2.3: Context awareness
- [ ] Read surrounding text from focused text field via Accessibility API (`AXUIElement`)
- [ ] Pass context to post-processor for style matching (e.g. matching case style, tone)

### 2.4: Local LLM integration
- [ ] Evaluate Apple `FoundationModels` framework (on-device, macOS 26)
- [ ] Evaluate `llama.cpp` / `MLX` as alternatives for more control
- [ ] Use local LLM for: rewriting, formatting commands, filler removal, style adaptation
- [ ] Keep latency under 500ms for the post-processing step

---

## Phase 3 — Advanced features (future)

### 3.1: Voice commands
- [ ] "Delete that" — remove last transcribed segment
- [ ] "New line" / "new paragraph" — insert line breaks
- [ ] "Select all" / "undo" — manipulate the overlay buffer
- [ ] Command detection (distinguish commands from dictation)

### 3.2: Custom dictionary
- [ ] User-managed word/phrase list
- [ ] Feed custom terms into transcription or post-processing to improve accuracy

### 3.3: Multi-language
- [ ] Language detection or manual language switching
- [ ] Hot-switch languages mid-session

### 3.4: Audio feedback
- [ ] Subtle sound on start/stop recording
- [ ] Haptic feedback (if on a MacBook with Force Touch trackpad)

---

## Non-goals

These are explicitly out of scope:

- **Cloud processing** — all transcription and processing stays on-device
- **iOS/iPadOS version** — macOS only for now (the API supports iOS 26 too, but the UX is desktop-focused)
- **App-specific integrations** — works universally via paste, no per-app plugins
- **Paid features / subscription** — fully free and open source
