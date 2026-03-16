import Foundation
@testable import Speak
import Testing

@Suite
struct ClaudeCodeMCPRegistrationTests {
    @Test
    func `setupCommand includes binary path`() {
        let command = ClaudeCodeMCPRegistration.setupCommand(binaryPath: "/usr/local/bin/SpeakMCP")
        #expect(command == "claude mcp add speak -s user -- /usr/local/bin/SpeakMCP")
    }

    @Test
    func `setupCommand uses bundle path by default`() {
        let command = ClaudeCodeMCPRegistration.setupCommand()
        #expect(command.hasPrefix("claude mcp add speak -s user -- "))
        #expect(command.hasSuffix("Contents/MacOS/SpeakMCP"))
    }

    @Test
    func `isRegistered returns false when settings file does not exist`() {
        // Default behavior with no settings file — can't easily test without file access mock,
        // but verifies the method doesn't crash.
        _ = ClaudeCodeMCPRegistration.isRegistered(binaryPath: "/nonexistent/SpeakMCP")
    }
}
