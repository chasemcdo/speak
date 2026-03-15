import Foundation
@testable import Speak
import Testing

private final class MockSettingsFileAccess: SettingsFileAccessing {
    var fileContents: Data?
    var writtenData: Data?
    var writeCalled = false

    func read() throws -> Data {
        guard let data = fileContents else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No file"])
        }
        return data
    }

    func write(_ data: Data) throws {
        writeCalled = true
        writtenData = data
    }

    func exists() -> Bool {
        fileContents != nil
    }

    func ensureDirectoryExists() throws {}
}

@Suite
struct ClaudeCodeMCPRegistrationTests {
    private let testBinaryPath = "/Applications/Speak.app/Contents/MacOS/SpeakMCP"

    private func parsedSettings(_ mock: MockSettingsFileAccess) throws -> [String: Any] {
        guard let data = mock.writtenData else {
            throw NSError(domain: "test", code: 2, userInfo: nil)
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test
    func `creates settings file when none exists`() throws {
        let mock = MockSettingsFileAccess()

        ClaudeCodeMCPRegistration.registerIfNeeded(fileAccess: mock, binaryPath: testBinaryPath)

        #expect(mock.writeCalled)
        let settings = try parsedSettings(mock)
        let mcpServers = try #require(settings["mcpServers"] as? [String: Any])
        let speak = try #require(mcpServers["speak"] as? [String: Any])
        #expect(speak["command"] as? String == testBinaryPath)
    }

    @Test
    func `adds speak to existing settings with no mcpServers`() throws {
        let mock = MockSettingsFileAccess()
        let existing: [String: Any] = ["permissions": ["allow": true]]
        mock.fileContents = try JSONSerialization.data(withJSONObject: existing)

        ClaudeCodeMCPRegistration.registerIfNeeded(fileAccess: mock, binaryPath: testBinaryPath)

        #expect(mock.writeCalled)
        let settings = try parsedSettings(mock)
        // Preserves existing keys
        #expect(settings["permissions"] != nil)
        let mcpServers = try #require(settings["mcpServers"] as? [String: Any])
        let speak = try #require(mcpServers["speak"] as? [String: Any])
        #expect(speak["command"] as? String == testBinaryPath)
    }

    @Test
    func `adds speak to existing mcpServers without overwriting others`() throws {
        let mock = MockSettingsFileAccess()
        let existing: [String: Any] = [
            "mcpServers": [
                "firebase": ["command": "/usr/local/bin/firebase-mcp"],
            ],
        ]
        mock.fileContents = try JSONSerialization.data(withJSONObject: existing)

        ClaudeCodeMCPRegistration.registerIfNeeded(fileAccess: mock, binaryPath: testBinaryPath)

        #expect(mock.writeCalled)
        let settings = try parsedSettings(mock)
        let mcpServers = try #require(settings["mcpServers"] as? [String: Any])
        // Firebase preserved
        let firebase = try #require(mcpServers["firebase"] as? [String: Any])
        #expect(firebase["command"] as? String == "/usr/local/bin/firebase-mcp")
        // Speak added
        let speak = try #require(mcpServers["speak"] as? [String: Any])
        #expect(speak["command"] as? String == testBinaryPath)
    }

    @Test
    func `updates command path when already registered with stale path`() throws {
        let mock = MockSettingsFileAccess()
        let existing: [String: Any] = [
            "mcpServers": [
                "speak": ["command": "/old/path/SpeakMCP"],
            ],
        ]
        mock.fileContents = try JSONSerialization.data(withJSONObject: existing)

        ClaudeCodeMCPRegistration.registerIfNeeded(fileAccess: mock, binaryPath: testBinaryPath)

        #expect(mock.writeCalled)
        let settings = try parsedSettings(mock)
        let mcpServers = try #require(settings["mcpServers"] as? [String: Any])
        let speak = try #require(mcpServers["speak"] as? [String: Any])
        #expect(speak["command"] as? String == testBinaryPath)
    }

    @Test
    func `no-ops when already correctly registered`() throws {
        let mock = MockSettingsFileAccess()
        let existing: [String: Any] = [
            "mcpServers": [
                "speak": ["command": testBinaryPath],
            ],
        ]
        mock.fileContents = try JSONSerialization.data(withJSONObject: existing)

        ClaudeCodeMCPRegistration.registerIfNeeded(fileAccess: mock, binaryPath: testBinaryPath)

        #expect(!mock.writeCalled)
    }

    @Test
    func `handles malformed JSON gracefully`() throws {
        let mock = MockSettingsFileAccess()
        mock.fileContents = Data("not valid json {{".utf8)

        ClaudeCodeMCPRegistration.registerIfNeeded(fileAccess: mock, binaryPath: testBinaryPath)

        // Should not crash; writes fresh config
        #expect(mock.writeCalled)
        let settings = try parsedSettings(mock)
        let mcpServers = try #require(settings["mcpServers"] as? [String: Any])
        let speak = try #require(mcpServers["speak"] as? [String: Any])
        #expect(speak["command"] as? String == testBinaryPath)
    }

    @Test
    func `resolves binary path from bundle`() {
        let bundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/SpeakMCP").path
        #expect(bundlePath.hasSuffix("Contents/MacOS/SpeakMCP"))
    }
}
