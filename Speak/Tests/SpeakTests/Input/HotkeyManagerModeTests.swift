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
struct HotkeyManagerModeTests {
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
        guard let spaceEvent = keyDownEvent(
            keyCode: 0x31, characters: " ", modifierFlags: .function
        ) else {
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

        guard let spaceEvent = keyDownEvent(
            keyCode: 0x31, characters: " ", modifierFlags: .function
        ) else {
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
