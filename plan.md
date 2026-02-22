# Phase 2 Implementation Plan — Post-Processing Pipeline

## Goal

Add a post-processing layer between transcription and paste that cleans up, formats, and optionally rewrites dictated text. Start with fast, deterministic transforms (filler removal, formatting) and graduate to Apple's on-device FoundationModels framework for intelligent rewriting. All processing stays on-device.

## What we're building on

Phase 1 is complete. The core loop works: fn → overlay → live transcription → paste. The insertion point is `AppCoordinator.confirm()` (line 92), where `let text = appState.displayText` is retrieved before being passed to `PasteService.paste()`. Phase 2 slots a processing pipeline between these two calls.

## New project structure

```
Speak/Speak/
├── ... (existing files unchanged)
│
├── PostProcessing/
│   ├── TextProcessor.swift          # Pipeline coordinator — chains transforms
│   ├── FillerWordFilter.swift       # Regex-based filler removal
│   ├── FormattingFilter.swift       # Capitalization, punctuation, paragraphs
│   ├── LLMRewriter.swift            # FoundationModels integration
│   └── ContextReader.swift          # Reads surrounding text via Accessibility API
```

## Implementation steps

Steps are ordered by dependency — each builds on the previous.

### Step 1: Post-processing pipeline architecture

Create the pluggable pipeline that all transforms plug into.

**Files:** `PostProcessing/TextProcessor.swift`

**What to build:**

```swift
/// A single text transformation step.
protocol TextFilter: Sendable {
    func apply(to text: String, context: ProcessingContext) async throws -> String
}

/// Context passed to each filter (surrounding text, user preferences, etc.)
struct ProcessingContext: Sendable {
    var surroundingText: String?
    var locale: Locale
}

/// Chains filters together and runs them in sequence.
@MainActor
@Observable
final class TextProcessor {
    var isProcessing = false

    private var filters: [TextFilter] = []

    func addFilter(_ filter: TextFilter) { filters.append(filter) }
    func removeAll() { filters.removeAll() }

    func process(_ text: String, context: ProcessingContext) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        var result = text
        for filter in filters {
            result = try await filter.apply(to: result, context: context)
        }
        return result
    }
}
```

**Wire into AppCoordinator.confirm():**

The current flow:
```swift
let text = appState.displayText
```

Becomes:
```swift
var text = appState.displayText
if !text.isEmpty {
    let context = ProcessingContext(
        surroundingText: nil,  // Step 5 adds this
        locale: /* current locale */
    )
    text = try await textProcessor.process(text, context: context)
}
```

**AppState additions:**
- `var isPostProcessing = false` — shown in overlay while processing

**Verify:** Pipeline runs with no filters (identity transform), text still pastes correctly.

### Step 2: Filler word removal

Strip common filler words and verbal tics. Pure regex — no LLM needed, runs in microseconds.

**Files:** `PostProcessing/FillerWordFilter.swift`

**What to build:**

```swift
struct FillerWordFilter: TextFilter {
    /// Default English fillers. User can customize via UserDefaults.
    static let defaultFillers = [
        "um", "uh", "uh huh", "uhh", "umm",
        "er", "ah", "hmm",
        "like",           // only when standalone filler, not "I like pizza"
        "you know",
        "I mean",
        "sort of",
        "kind of",
        "basically",
        "actually",       // when sentence-initial filler
        "right",          // when used as verbal tic, not affirmation
        "so yeah",
    ]

    func apply(to text: String, context: ProcessingContext) async throws -> String {
        // Build regex patterns that match fillers at word boundaries
        // Handle edge cases: don't strip "like" from "I like pizza"
        // Clean up resulting double spaces
    }
}
```

**Key considerations:**
- Word-boundary matching (`\b`) to avoid stripping substrings
- "like" is tricky — only strip when it appears as a standalone filler (e.g. "I was, like, going"), not as a verb. Start conservative: only strip clearly-standalone patterns like ", like," and "like, " at sentence starts. Can improve with LLM in Step 4.
- Normalize whitespace after removal (collapse double spaces, trim)
- Make the filler list user-configurable via UserDefaults with a default set

**Settings additions:**
- Toggle: "Remove filler words" (`@AppStorage("removeFillerWords")`, default: true)
- Future: editable filler word list

**Verify:** "Um, I was, like, thinking we should, you know, go to the store" → "I was thinking we should go to the store"

### Step 3: Basic formatting

Auto-capitalize, smart punctuation, and paragraph detection from pauses.

**Files:** `PostProcessing/FormattingFilter.swift`

**What to build:**

```swift
struct FormattingFilter: TextFilter {
    func apply(to text: String, context: ProcessingContext) async throws -> String {
        var result = text

        // 1. Auto-capitalize after sentence-ending punctuation
        result = capitalizeSentenceStarts(result)

        // 2. Smart punctuation
        //    - Straight quotes → curly quotes
        //    - Double hyphens → em dashes
        //    - Three dots → ellipsis character

        // 3. Trim trailing whitespace/incomplete fragments

        return result
    }
}
```

**Key considerations:**
- SpeechTranscriber already handles basic capitalization and punctuation in many cases — this filter catches what it misses and normalizes inconsistencies
- Keep transforms idempotent (running twice shouldn't change the result)
- Respect locale for quote style (e.g. „German" vs "English")

**Settings additions:**
- Toggle: "Auto-format text" (`@AppStorage("autoFormat")`, default: true)

**Verify:** "hello world. this is a test" → "Hello world. This is a test"

### Step 4: Local LLM integration via FoundationModels

Use Apple's on-device ~3B parameter model for intelligent text cleanup: better filler removal, grammar correction, conciseness, and style adaptation.

**Files:** `PostProcessing/LLMRewriter.swift`

**What to build:**

```swift
import FoundationModels

/// Uses Apple's on-device LLM to rewrite/clean transcribed text.
struct LLMRewriter: TextFilter {
    func apply(to text: String, context: ProcessingContext) async throws -> String {
        // Check model availability
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            return text  // Graceful fallback: skip LLM, return text as-is
        }

        let session = LanguageModelSession {
            """
            You are a text cleanup assistant for a dictation app. Your job is to take
            raw transcribed speech and clean it up for written communication.

            Rules:
            - Remove filler words (um, uh, like, you know, etc.)
            - Fix grammar and punctuation
            - Keep the meaning and tone identical to the original
            - Do NOT add information, opinions, or change the intent
            - Do NOT make the text more formal unless the context suggests it
            - Return ONLY the cleaned text, no commentary
            """
        }

        // If we have surrounding text context, include it
        var prompt = "Clean up this transcribed speech:\n\n\(text)"
        if let surrounding = context.surroundingText, !surrounding.isEmpty {
            prompt = """
            The user is writing in this context:
            ---
            \(surrounding)
            ---

            Clean up this transcribed speech to match the style above:
            \(text)
            """
        }

        let response = try await session.respond(to: prompt)
        let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Sanity check: if the LLM returned something drastically different
        // in length, fall back to the original (hallucination guard)
        let ratio = Double(cleaned.count) / Double(text.count)
        if ratio < 0.3 || ratio > 2.0 {
            return text
        }

        return cleaned
    }
}
```

**Key technical details:**
- **FoundationModels** requires macOS 26, Apple Silicon (M1+), Apple Intelligence enabled
- ~3B parameter model, runs on-device, ~30 tokens/sec on iPhone 15 Pro (faster on Mac)
- 4096 token context window (combined input + output) — sufficient for dictation segments
- Text refinement is explicitly one of the model's core strengths
- WWDC25 SpeechAnalyzer session directly demonstrates using FoundationModels to post-process transcription output
- `LanguageModelSession.prewarm()` can be called when the user starts recording to reduce first-response latency

**Performance target:** < 500ms for typical dictation segments (1-3 sentences). The on-device model at 30+ tok/s should handle this easily for short text.

**Availability handling:**
- Check `SystemLanguageModel.default.availability` before every call
- If `.unavailable(.appleIntelligenceNotEnabled)` → show a hint in settings
- If `.unavailable(.deviceNotEligible)` → hide the toggle entirely
- If `.unavailable(.modelNotReady)` → skip silently, use regex filters only

**Settings additions:**
- Toggle: "AI-powered cleanup" (`@AppStorage("llmRewrite")`, default: false — opt-in initially)
- Show availability status and guidance if unavailable

**Package.swift addition:**
```swift
.linkedFramework("FoundationModels")
```

**Verify:** "um I was thinking that we should like go to the meeting at like 3 pm and uh discuss the project" → "I was thinking we should go to the meeting at 3 PM and discuss the project"

### Step 5: Context awareness via Accessibility API

Read surrounding text from the focused text field to give the LLM style context.

**Files:** `PostProcessing/ContextReader.swift`

**What to build:**

```swift
import AppKit

/// Reads text from the currently focused text field via the Accessibility API.
@MainActor
final class ContextReader {
    /// Get the text surrounding the cursor in the focused text field.
    /// Returns nil if inaccessible (app doesn't expose AX, no text field focused, etc.)
    func readContext(from app: NSRunningApplication?) -> String? {
        guard let app, let pid = Optional(app.processIdentifier) else { return nil }

        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused UI element
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            return nil
        }

        let axElement = element as! AXUIElement

        // Read the text value
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else {
            return nil
        }

        // Trim to last ~500 characters for context (keep within LLM token budget)
        let maxContext = 500
        if text.count > maxContext {
            return String(text.suffix(maxContext))
        }

        return text
    }
}
```

**Wire into AppCoordinator:**
- Call `contextReader.readContext(from: previousApp)` before starting transcription (while the previous app still has a focused text field)
- Pass the context through `ProcessingContext.surroundingText` to the LLM filter

**Key considerations:**
- Accessibility permission is already required for paste (CGEvent posting)
- Not all apps expose their text fields via AX — fail gracefully (return nil)
- Keep context short (~500 chars) to stay well within the 4096 token budget
- Read context at the *start* of dictation (before overlay appears), not at the end

**Verify:** When dictating in a Slack message that starts with "Hey team, quick update on the Q4 numbers:", the LLM uses that context to match the informal tone.

### Step 6: Settings UI for post-processing

Add a "Post-Processing" section to SettingsView.

**Files:** Update `Settings/SettingsView.swift`

**What to build:**

```swift
Section("Post-Processing") {
    Toggle("Remove filler words", isOn: $removeFillerWords)
        .help("Strip 'um', 'uh', 'like', 'you know', etc.")

    Toggle("Auto-format text", isOn: $autoFormat)
        .help("Auto-capitalize and clean up punctuation.")

    Toggle("AI-powered cleanup", isOn: $llmRewrite)
        .help("Use Apple Intelligence to rewrite transcribed text for clarity.")
        .disabled(!llmAvailable)

    if !llmAvailable {
        Text("Requires Apple Intelligence to be enabled in System Settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**Verify:** Toggles persist, enabling/disabling each filter changes output.

### Step 7: Overlay updates

Show post-processing state in the overlay after recording stops.

**Files:** Update `Overlay/OverlayView.swift`, `Models/AppState.swift`

**What to build:**
- When recording stops and post-processing begins, briefly show a "Formatting..." indicator in the overlay instead of immediately hiding it
- If LLM rewriting is enabled, show a subtle progress state (< 500ms, so it's brief)
- The overlay hides after processing completes

**AppState additions:**
```swift
var isPostProcessing = false
```

**AppCoordinator changes:**
- Set `appState.isPostProcessing = true` before running the pipeline
- Set `appState.isPostProcessing = false` after
- Only hide overlay after processing finishes

**Verify:** Brief "Formatting..." appears after confirming dictation when LLM is enabled.

### Step 8: Prewarm and performance optimization

Ensure the LLM is ready by the time the user finishes dictating.

**What to build:**
- Call `LanguageModelSession.prewarm()` when the app launches or when the user starts recording
- Measure end-to-end latency from confirm → paste, ensure < 500ms for regex-only, < 1s for LLM
- If LLM takes too long (> 2s timeout), fall back to regex-only result and paste immediately

**Verify:** Confirm-to-paste latency feels instant with regex filters, barely noticeable with LLM.

## Filter execution order

When all filters are enabled, they run in this order:

1. **FillerWordFilter** — fast regex pass, strips obvious fillers
2. **FormattingFilter** — capitalizes, fixes punctuation
3. **LLMRewriter** — intelligent rewrite (if enabled and available)

The LLM runs last because it can handle anything the regex filters miss, and feeding it already-cleaned text produces better results. If the LLM is disabled, steps 1-2 alone still provide significant value.

## What's explicitly NOT in this plan

- Voice commands ("delete that", "new paragraph") — Phase 3
- Custom dictionary / vocabulary — Phase 3
- Multi-language hot-switching — Phase 3
- Training custom FoundationModels adapters — future optimization
- Cloud/server-side processing — non-goal (everything stays on-device)

## Open decisions

1. **Filler word "like" handling** — Regex can catch obvious patterns (", like,") but will miss some. The LLM handles this well. Start conservative with regex, let LLM catch the rest. Monitor false positives.

2. **LLM opt-in vs opt-out** — Start as opt-in (off by default) since it adds latency and requires Apple Intelligence. Flip to opt-out once we're confident in quality and speed.

3. **Context window management** — With 4096 tokens, we need to budget: ~500 tokens for system prompt, ~500 for surrounding context, leaving ~3000 for the actual transcription. For very long dictation, may need to process in chunks or skip context.

4. **Overlay behavior during processing** — Should we hide the overlay immediately (feels faster) or keep it until processing finishes (shows the cleaned result)? Start with keeping it visible for feedback; can change based on user preference.

## Reference

- [FoundationModels documentation](https://developer.apple.com/documentation/FoundationModels)
- [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25: Deep dive into Foundation Models](https://developer.apple.com/videos/play/wwdc2025/301/)
- [WWDC25: Bring advanced speech-to-text with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/) — shows FoundationModels post-processing transcription output
- [Apple ML Research: Foundation Models 2025 Updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [ARCHITECTURE.md](ARCHITECTURE.md) — component design and data flow
- [ROADMAP.md](ROADMAP.md) — milestone checklist
