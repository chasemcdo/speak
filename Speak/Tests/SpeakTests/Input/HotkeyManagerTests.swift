import AppKit
@testable import Speak
import Testing

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
private func keyDownEvent(keyCode: UInt16, characters: String = "",
                          modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent? {
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

@Suite(.serialized)
struct HotkeyManagerTests {
    // MARK: - Basic hold flow

    @Test @MainActor
    func `hold and release fn triggers start then stop`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var startCalled = false
        var stopCalled = false

        manager.register(
            onStart: { startCalled = true },
            onStop: { stopCalled = true },
            onModeChange: { _ in },
            onConversationToggle: {}
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
    func `spacebar during hold transitions to toggle`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var startCalled = false
        var stopCalled = false

        manager.register(
            onStart: { startCalled = true },
            onStop: { stopCalled = true },
            onModeChange: { _ in },
            onConversationToggle: {}
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
    func `non spacebar key during hold is not consumed`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        manager.register(onStart: {}, onStop: {}, onModeChange: { _ in }, onConversationToggle: {})

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
    func `spacebar in idle state is not consumed`() {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        manager.register(onStart: {}, onStop: {}, onModeChange: { _ in }, onConversationToggle: {})

        guard let spaceEvent = keyDownEvent(keyCode: 0x31, characters: " ") else {
            Issue.record("Failed to create keyDown event")
            return
        }
        let consumed = manager.handleKeyDown(spaceEvent)
        #expect(!consumed)

        manager.unregister()
    }

    @Test @MainActor
    func `spacebar in toggle recording is not consumed`() {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        manager.register(onStart: {}, onStop: {}, onModeChange: { _ in }, onConversationToggle: {})

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
    func `double tap triggers start and subsequent tap stops`() {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var startCalled = false
        var stopCalled = false

        manager.register(
            onStart: { startCalled = true },
            onStop: { stopCalled = true },
            onModeChange: { _ in },
            onConversationToggle: {}
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
    func `reset state prevents stop on release`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var stopCalled = false
        manager.register(onStart: {}, onStop: { stopCalled = true }, onModeChange: { _ in }, onConversationToggle: {})

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
    func `other modifier during hold stops recording`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var stopCalled = false
        manager.register(onStart: {}, onStop: { stopCalled = true }, onModeChange: { _ in }, onConversationToggle: {})

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

    // MARK: - Mode change callbacks

    @Test @MainActor
    func `hold activation fires mode change hold`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var modeChanges: [RecordingMode] = []

        manager.register(
            onStart: {},
            onStop: {},
            onModeChange: { modeChanges.append($0) },
            onConversationToggle: {}
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function) else {
            Issue.record("Failed to create event")
            return
        }
        manager.handleFlagsChanged(downEvent)

        // Wait for hold threshold
        try await Task.sleep(for: .milliseconds(400))

        #expect(modeChanges == [.hold])

        manager.unregister()
    }

    @Test @MainActor
    func `double tap fires mode change toggle`() {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var modeChanges: [RecordingMode] = []

        manager.register(
            onStart: {},
            onStop: {},
            onModeChange: { modeChanges.append($0) },
            onConversationToggle: {}
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Double-tap: first tap
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent)

        // Second tap press (triggers onStart)
        manager.handleFlagsChanged(downEvent)
        #expect(modeChanges.isEmpty) // Not yet — fires on release

        // Second tap release → enters toggleRecording
        manager.handleFlagsChanged(upEvent)
        #expect(modeChanges == [.toggle])

        manager.unregister()
    }

    @Test @MainActor
    func `spacebar transition fires mode change toggle`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var modeChanges: [RecordingMode] = []

        manager.register(
            onStart: {},
            onStop: {},
            onModeChange: { modeChanges.append($0) },
            onConversationToggle: {}
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function) else {
            Issue.record("Failed to create event")
            return
        }
        manager.handleFlagsChanged(downEvent)

        // Wait for hold threshold → fires .hold
        try await Task.sleep(for: .milliseconds(400))
        #expect(modeChanges == [.hold])

        // Spacebar → fires .toggle
        guard let spaceEvent = keyDownEvent(keyCode: 0x31, characters: " ", modifierFlags: .function) else {
            Issue.record("Failed to create keyDown event")
            return
        }
        manager.handleKeyDown(spaceEvent)
        #expect(modeChanges == [.hold, .toggle])

        manager.unregister()
    }

    @Test @MainActor
    func `quick single tap fires no mode change`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var modeChanges: [RecordingMode] = []

        manager.register(
            onStart: {},
            onStop: {},
            onModeChange: { modeChanges.append($0) },
            onConversationToggle: {}
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Quick tap — release before hold threshold
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent)

        // Wait for double-tap window to expire
        try await Task.sleep(for: .milliseconds(400))

        #expect(modeChanges.isEmpty)

        manager.unregister()
    }

    @Test @MainActor
    func `reset state during hold fires no extra mode change`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var modeChanges: [RecordingMode] = []

        manager.register(
            onStart: {},
            onStop: {},
            onModeChange: { modeChanges.append($0) },
            onConversationToggle: {}
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Enter hold mode
        manager.handleFlagsChanged(downEvent)
        try await Task.sleep(for: .milliseconds(400))
        #expect(modeChanges == [.hold])

        // Reset externally
        manager.resetState()

        // Release — should NOT fire additional mode change
        manager.handleFlagsChanged(upEvent)
        #expect(modeChanges == [.hold])

        manager.unregister()
    }

    @Test @MainActor
    func `multiple spacebar presses fires toggle only once`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var modeChanges: [RecordingMode] = []

        manager.register(
            onStart: {},
            onStop: {},
            onModeChange: { modeChanges.append($0) },
            onConversationToggle: {}
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function) else {
            Issue.record("Failed to create event")
            return
        }
        manager.handleFlagsChanged(downEvent)

        // Wait for hold threshold
        try await Task.sleep(for: .milliseconds(400))
        #expect(modeChanges == [.hold])

        guard let spaceEvent = keyDownEvent(keyCode: 0x31, characters: " ", modifierFlags: .function) else {
            Issue.record("Failed to create keyDown event")
            return
        }

        // First spacebar → transition to toggle
        manager.handleKeyDown(spaceEvent)
        #expect(modeChanges == [.hold, .toggle])

        // Second spacebar → already in toggleRecording, not consumed
        let consumed = manager.handleKeyDown(spaceEvent)
        #expect(!consumed)
        #expect(modeChanges == [.hold, .toggle])

        manager.unregister()
    }

    // MARK: - Triple-tap conversation toggle

    @Test @MainActor
    func `triple tap triggers conversation toggle`() {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var conversationToggled = false
        var stopCalled = false

        manager.register(
            onStart: {},
            onStop: { stopCalled = true },
            onModeChange: { _ in },
            onConversationToggle: { conversationToggled = true }
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Double-tap to start toggle recording
        manager.handleFlagsChanged(downEvent) // firstDown
        manager.handleFlagsChanged(upEvent) // awaitingSecondTap
        manager.handleFlagsChanged(downEvent) // doubleTapDown (onStart fires)
        manager.handleFlagsChanged(upEvent) // toggleRecording (sets toggleEnteredTime)

        // Third tap immediately — within doubleTapWindow
        manager.handleFlagsChanged(downEvent) // tripleTapDown (onStop fires)
        #expect(stopCalled)

        manager.handleFlagsChanged(upEvent) // idle (onConversationToggle fires)
        #expect(conversationToggled)

        manager.unregister()
    }

    @Test @MainActor
    func `triple tap after window expires does normal stop`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var conversationToggled = false
        var stopCalled = false

        manager.register(
            onStart: {},
            onStop: { stopCalled = true },
            onModeChange: { _ in },
            onConversationToggle: { conversationToggled = true }
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Double-tap to start toggle recording
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent)
        manager.handleFlagsChanged(downEvent)
        manager.handleFlagsChanged(upEvent) // toggleRecording

        // Wait past the double-tap window
        try await Task.sleep(for: .milliseconds(400))

        // Tap to stop — should be normal stop, not conversation toggle
        manager.handleFlagsChanged(downEvent) // toggleTapDown (not tripleTapDown)
        manager.handleFlagsChanged(upEvent) // idle + onStop
        #expect(stopCalled)
        #expect(!conversationToggled)

        manager.unregister()
    }

    @Test @MainActor
    func `triple tap during hold does not trigger conversation`() async throws {
        UserDefaults.standard.set("fn", forKey: "hotkeyModifier")

        let manager = HotkeyManager()
        var conversationToggled = false

        manager.register(
            onStart: {},
            onStop: {},
            onModeChange: { _ in },
            onConversationToggle: { conversationToggled = true }
        )

        guard let downEvent = flagsChangedEvent(modifierFlags: .function),
              let upEvent = flagsChangedEvent(modifierFlags: []) else {
            Issue.record("Failed to create events")
            return
        }

        // Hold mode
        manager.handleFlagsChanged(downEvent)
        try await Task.sleep(for: .milliseconds(400))

        // Release hold
        manager.handleFlagsChanged(upEvent)

        #expect(!conversationToggled)

        manager.unregister()
    }
}
