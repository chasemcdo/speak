import AppKit
import Carbon
import CoreGraphics

/// The modifier key used to toggle dictation.
enum TranscriptionHotkey: String, CaseIterable {
    case fn
    case control
    case option
    case command

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .control: return .control
        case .option: return .option
        case .command: return .command
        }
    }

    var label: String {
        switch self {
        case .fn: return "fn"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        }
    }

    var shortLabel: String {
        switch self {
        case .fn: return "fn"
        case .control: return "⌃"
        case .option: return "⌥"
        case .command: return "⌘"
        }
    }

    /// The currently configured hotkey, read from UserDefaults.
    static var current: TranscriptionHotkey {
        TranscriptionHotkey(rawValue: UserDefaults.standard.string(forKey: "hotkeyModifier") ?? "") ?? .fn
    }
}

/// Manages the global hotkey for toggling dictation.
///
/// Supports two activation gestures:
/// - **Double-tap**: Starts recording in "toggle" mode. A subsequent single tap stops it.
/// - **Hold**: Starts recording while held. Releasing the key stops it.
final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyDownGlobalMonitor: Any?
    private var keyDownLocalMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var onStart: (() -> Void)?
    private var onStop: (() -> Void)?

    /// Internal state machine for gesture recognition.
    private enum State {
        case idle
        /// Hotkey pressed; could become a hold or the first tap of a double-tap.
        case firstDown
        /// First tap completed (quick press-release), waiting for a potential second tap.
        case awaitingSecondTap
        /// Hotkey held past the hold threshold — recording in hold mode.
        case holdRecording
        /// Second tap pressed — recording just started, waiting for release.
        case doubleTapDown
        /// Double-tap completed, recording until the next single tap stops it.
        case toggleRecording
        /// In toggle-recording mode, hotkey pressed to stop.
        case toggleTapDown
    }

    private var state: State = .idle
    private var hotkeyDown = false

    // MARK: - Timers

    private var holdTimer: DispatchWorkItem?
    private var doubleTapTimer: DispatchWorkItem?

    /// How long the hotkey must be held before activating hold-to-record (seconds).
    private let holdThreshold: TimeInterval = 0.3
    /// Maximum gap between two taps to register as a double-tap (seconds).
    private let doubleTapWindow: TimeInterval = 0.3

    // MARK: - Public API

    func register(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onStart = onStart
        self.onStop = onStop

        // Monitor flagsChanged for the configured modifier key (works system-wide)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        onStart = nil
        onStop = nil
        cancelTimers()
        removeKeyDownMonitor()
        state = .idle
        hotkeyDown = false
    }

    /// Reset the state machine back to idle. Call this when recording is stopped
    /// externally (e.g. via Enter/Escape keys or the menu bar).
    func resetState() {
        cancelTimers()
        removeKeyDownMonitor()
        state = .idle
    }

    // MARK: - Spacebar hold-to-persist

    /// Install a monitor to detect spacebar during hold recording.
    /// Uses a CGEventTap when Accessibility permission is available so the space
    /// keystroke can be suppressed before it reaches the foreground app. Falls back
    /// to NSEvent monitors otherwise (state transition works, but the space leaks).
    private func installKeyDownMonitor() {
        guard eventTap == nil, keyDownGlobalMonitor == nil else { return }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                // Re-enable if the system disabled the tap due to timeout
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown else { return Unmanaged.passUnretained(event) }

                // Suppress spacebar during hold recording
                if event.getIntegerValueField(.keyboardEventKeycode) == 0x31,
                   manager.state == .holdRecording {
                    manager.state = .toggleRecording
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            eventTapRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // Fallback: NSEvent monitors detect the space but cannot suppress it
            keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
            }
            keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = self?.handleKeyDown(event) ?? false
                return consumed ? nil : event
            }
        }
    }

    /// Remove the keyDown monitors (event tap and/or NSEvent monitors).
    private func removeKeyDownMonitor() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let eventTapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            }
        }
        eventTap = nil
        eventTapRunLoopSource = nil

        if let keyDownGlobalMonitor {
            NSEvent.removeMonitor(keyDownGlobalMonitor)
        }
        if let keyDownLocalMonitor {
            NSEvent.removeMonitor(keyDownLocalMonitor)
        }
        keyDownGlobalMonitor = nil
        keyDownLocalMonitor = nil
    }

    /// Handle a keyDown event. Returns `true` if the event was consumed.
    /// Internal for testability — called by keyDown monitors.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.keyCode == 0x31, state == .holdRecording else { return false }
        state = .toggleRecording
        removeKeyDownMonitor()
        return true
    }

    // MARK: - Event handling

    /// Internal for testability — called by flagsChanged monitors.
    func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hotkey = TranscriptionHotkey.current
        let keyIsDown = flags.contains(hotkey.modifierFlag) && flags.subtracting(hotkey.modifierFlag).isEmpty
        let keyIsUp = !flags.contains(hotkey.modifierFlag)
        let otherModifiers = flags.contains(hotkey.modifierFlag) && !flags.subtracting(hotkey.modifierFlag).isEmpty

        if keyIsDown && !hotkeyDown {
            hotkeyDown = true
            handleHotkeyPressed()
        } else if keyIsUp && hotkeyDown {
            hotkeyDown = false
            handleHotkeyReleased()
        } else if otherModifiers && hotkeyDown {
            // Another modifier added while hotkey was held — cancel current gesture
            hotkeyDown = false
            handleOtherModifier()
        }
    }

    private func handleHotkeyPressed() {
        switch state {
        case .idle:
            // Start the hold timer — if key stays down long enough, enter hold mode
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.state == .firstDown else { return }
                self.state = .holdRecording
                self.installKeyDownMonitor()
                self.onStart?()
            }
            holdTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
            state = .firstDown

        case .awaitingSecondTap:
            // Second tap detected — this is a double-tap. Start recording.
            doubleTapTimer?.cancel()
            doubleTapTimer = nil
            state = .doubleTapDown
            onStart?()

        case .toggleRecording:
            // User is tapping hotkey to stop toggle-mode recording
            state = .toggleTapDown

        default:
            break
        }
    }

    private func handleHotkeyReleased() {
        switch state {
        case .firstDown:
            // Quick tap — released before hold threshold. Wait for potential second tap.
            holdTimer?.cancel()
            holdTimer = nil

            let work = DispatchWorkItem { [weak self] in
                guard let self, self.state == .awaitingSecondTap else { return }
                // Double-tap window expired — this was just a single tap while idle. No-op.
                self.state = .idle
            }
            doubleTapTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
            state = .awaitingSecondTap

        case .holdRecording:
            // Released after hold — stop recording
            removeKeyDownMonitor()
            state = .idle
            onStop?()

        case .doubleTapDown:
            // Release after the second tap of a double-tap — ignore this release,
            // recording continues in toggle mode.
            state = .toggleRecording

        case .toggleTapDown:
            // Release after tapping to stop toggle-mode recording
            state = .idle
            onStop?()

        default:
            break
        }
    }

    private func handleOtherModifier() {
        switch state {
        case .firstDown:
            // Cancel the gesture — another key was pressed during hold
            holdTimer?.cancel()
            holdTimer = nil
            state = .idle

        case .holdRecording:
            // Stop recording if modifiers get mixed
            removeKeyDownMonitor()
            state = .idle
            onStop?()

        default:
            // For awaitingSecondTap, toggleRecording, etc. — hotkey isn't held, so
            // other modifiers don't affect us. But reset firstDown-like states.
            cancelTimers()
            state = .idle
        }
    }

    // MARK: - Helpers

    private func cancelTimers() {
        holdTimer?.cancel()
        holdTimer = nil
        doubleTapTimer?.cancel()
        doubleTapTimer = nil
    }

    deinit {
        unregister()
    }
}
