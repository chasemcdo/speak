import AppKit
import Carbon

/// Manages the global hotkey (fn key by default) for toggling dictation.
///
/// Supports two activation gestures:
/// - **Double-tap fn**: Starts recording in "toggle" mode. A subsequent single tap stops it.
/// - **Hold fn**: Starts recording while held. Releasing fn stops it.
final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onStart: (() -> Void)?
    private var onStop: (() -> Void)?

    /// Internal state machine for gesture recognition.
    private enum State {
        case idle
        /// fn pressed; could become a hold or the first tap of a double-tap.
        case firstDown
        /// First tap completed (quick press-release), waiting for a potential second tap.
        case awaitingSecondTap
        /// fn held past the hold threshold — recording in hold mode.
        case holdRecording
        /// Second tap fn is pressed — recording just started, waiting for release.
        case doubleTapDown
        /// Double-tap completed, recording until the next single tap stops it.
        case toggleRecording
        /// In toggle-recording mode, fn pressed to stop.
        case toggleTapDown
    }

    private var state: State = .idle
    private var fnKeyDown = false

    // MARK: - Timers

    private var holdTimer: DispatchWorkItem?
    private var doubleTapTimer: DispatchWorkItem?

    /// How long fn must be held before activating hold-to-record (seconds).
    private let holdThreshold: TimeInterval = 0.3
    /// Maximum gap between two taps to register as a double-tap (seconds).
    private let doubleTapWindow: TimeInterval = 0.3

    // MARK: - Public API

    func register(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onStart = onStart
        self.onStop = onStop

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
        state = .idle
        fnKeyDown = false
    }

    /// Reset the state machine back to idle. Call this when recording is stopped
    /// externally (e.g. via Enter/Escape keys or the menu bar).
    func resetState() {
        cancelTimers()
        state = .idle
    }

    // MARK: - Event handling

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let fnIsDown = flags.contains(.function) && flags.subtracting(.function).isEmpty
        let fnIsUp = !flags.contains(.function)
        let otherModifiers = flags.contains(.function) && !flags.subtracting(.function).isEmpty

        if fnIsDown && !fnKeyDown {
            fnKeyDown = true
            handleFnPressed()
        } else if fnIsUp && fnKeyDown {
            fnKeyDown = false
            handleFnReleased()
        } else if otherModifiers && fnKeyDown {
            // Another modifier added while fn was held — cancel current gesture
            fnKeyDown = false
            handleOtherModifier()
        }
    }

    private func handleFnPressed() {
        switch state {
        case .idle:
            // Start the hold timer — if fn stays down long enough, enter hold mode
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.state == .firstDown else { return }
                self.state = .holdRecording
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
            // User is tapping fn to stop toggle-mode recording
            state = .toggleTapDown

        default:
            break
        }
    }

    private func handleFnReleased() {
        switch state {
        case .firstDown:
            // Quick tap — fn released before hold threshold. Wait for potential second tap.
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
            // Cancel the gesture — another key was pressed during fn hold
            holdTimer?.cancel()
            holdTimer = nil
            state = .idle

        case .holdRecording:
            // Stop recording if modifiers get mixed
            state = .idle
            onStop?()

        default:
            // For awaitingSecondTap, toggleRecording, etc. — fn isn't held, so
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
