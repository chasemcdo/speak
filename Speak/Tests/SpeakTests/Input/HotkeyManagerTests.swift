import AppKit
import Testing
@testable import Speak

/// Helper to create synthetic flagsChanged events for testing.
private func flagsChangedEvent(modifierFlags: NSEvent.ModifierFlags) -> NSEvent? {
    NSEvent.keyEvent(
        with: .flagsChanged,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: 0
    )
}

/// Helper to create synthetic keyDown events for testing.
private func keyDownEvent(keyCode: UInt16, characters: String = "", modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )
}

@Suite("HotkeyManager")
struct HotkeyManagerTests {

    // MARK: - Basic hold flow

    @Test @MainActor
    func holdAndReleaseFnTriggersStartThenStop() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var startCalled = false
        var stopCalled = false

        manager.register(
            onStart: { startCalled = true },
            onStop: { stopCalled = true }
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function) else {
            Issue.record("Failed to create flagsChanged event")
            return
        }
        manager.handleFlagsChanged(downEvent)

        // Wait for hold threshold (0.3s + margin)
        try await Task.sleep(for: .milliseconds(400))
        #expect(startCalled)

        guard let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create flagsChanged event")
            return
        }
        manager.handleFlagsChanged(upEvent)
        #expect(stopCalled)

        manager.unregister()
    }

    // MARK: - Spacebar hold-to-persist

    @Test @MainActor
    func spacebarDuringHoldTransitionsToToggle() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var startCalled = false
        var stopCalled = false

        manager.register(
            onStart: { startCalled = true },
            onStop: { stopCalled = true }
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Press fn
        manager.handleFlagsChanged(downEvent)

        // Wait for hold threshold to enter holdRecording
        try await Task.sleep(for: .milliseconds(400))
        #expect(startCalled)

        // Press spacebar while holding fn → transition to toggleRecording
        guard let spaceEvent = keyDownEvent(keyCode: 0x31, characters: " ", modifierFlags: .function) else {
            Issue.record("Failed to create keyDown event")
            return
        }
        let consumed = manager.handleKeyDown(spaceEvent)
        #expect(consumed)

        // Release fn — should NOT trigger stop (now in toggleRecording)
        manager.handleFlagsChanged(upEvent)
        #expect(!stopCalled)

        // Tap fn again to stop (press → toggleTapDown, release → idle + onStop)
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent)
        #expect(stopCalled)

        manager.unregister()
    }

    @Test @MainActor
    func nonSpacebarKeyDuringHoldIsNotConsumed() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        manager.register(onStart: {}, onStop: {})

        guard let downEvent = flagsChangedEvent(modifierFlags: .function) else {
            Issue.record("Failed to create event")
            return
        }
        manager.handleFlagsChanged(downEvent)

        // Wait for hold threshold
        try await Task.sleep(for: .milliseconds(400))

        // Press 'a' key (keyCode 0x00) — should NOT be consumed
        guard let aEvent = keyDownEvent(keyCode: 0x00, characters: "a", modifierFlags: .function) else {
            Issue.record("Failed to create keyDown event")
            return
        }
        let consumed = manager.handleKeyDown(aEvent)
        #expect(!consumed)

        manager.unregister()
    }

    @Test @MainActor
    func spacebarInIdleStateIsNotConsumed() {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        manager.register(onStart: {}, onStop: {})

        guard let spaceEvent = keyDownEvent(keyCode: 0x31, characters: " ") else {
            Issue.record("Failed to create keyDown event")
            return
        }
        let consumed = manager.handleKeyDown(spaceEvent)
        #expect(!consumed)

        manager.unregister()
    }

    @Test @MainActor
    func spacebarInToggleRecordingIsNotConsumed() async {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        manager.register(onStart: {}, onStop: {})

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Double-tap to enter toggleRecording
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent)
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent) // now in toggleRecording

        // Spacebar should not be consumed in toggleRecording
        guard let spaceEvent = keyDownEvent(keyCode: 0x31, characters: " ") else {
            Issue.record("Failed to create keyDown event")
            return
        }
        let consumed = manager.handleKeyDown(spaceEvent)
        #expect(!consumed)

        manager.unregister()
    }

    // MARK: - Double-tap still works (no regression)

    @Test @MainActor
    func doubleTapTriggersStartAndSubsequentTapStops() async {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var startCalled = false
        var stopCalled = false

        manager.register(
            onStart: { startCalled = true },
            onStop: { stopCalled = true }
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // First tap (quick press-release)
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent)

        // Second tap within double-tap window
        manager.handleFlagsChanged(downEvent)
        #expect(startCalled)

        // Release second tap — enters toggleRecording
        manager.handleFlagsChanged(upEvent)
        #expect(!stopCalled)

        // Tap to stop
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent)
        #expect(stopCalled)

        manager.unregister()
    }

    // MARK: - resetState

    @Test @MainActor
    func resetStatePreventsStopOnRelease() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var stopCalled = false
        manager.register(onStart: {}, onStop: { stopCalled = true })

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Press fn, enter holdRecording
        manager.handleFlagsChanged(downEvent)
        try await Task.sleep(for: .milliseconds(400))

        // Reset externally (as if Escape was pressed)
        manager.resetState()

        // Release fn — should NOT trigger stop since state was reset to idle
        manager.handleFlagsChanged(upEvent)
        #expect(!stopCalled)

        manager.unregister()
    }

    // MARK: - Other modifier cancels hold

    @Test @MainActor
    func otherModifierDuringHoldStopsRecording() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var stopCalled = false
        manager.register(onStart: {}, onStop: { stopCalled = true })

        guard let downEvent = flagsChangedEvent(modifierFlags: .function) else {
            Issue.record("Failed to create event")
            return
        }

        // Press fn, enter holdRecording
        manager.handleFlagsChanged(downEvent)
        try await Task.sleep(for: .milliseconds(400))

        // Press fn + command (other modifier added)
        guard let mixedEvent = flagsChangedEvent(modifierFlags: [.function, .command]) else {
            Issue.record("Failed to create event")
            return
        }
        manager.handleFlagsChanged(mixedEvent)
        #expect(stopCalled)

        manager.unregister()
    }
}
