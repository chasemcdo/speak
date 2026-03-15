import Foundation

/// Provides file system access to Claude Code's settings file for testability.
protocol SettingsFileAccessing {
    func read() throws -> Data
    func write(_ data: Data) throws
    func exists() -> Bool
    func ensureDirectoryExists() throws
}

/// Default implementation targeting `~/.claude/settings.json`.
private struct RealSettingsFileAccess: SettingsFileAccessing {
    private let fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    func read() throws -> Data {
        try Data(contentsOf: fileURL)
    }

    func write(_ data: Data) throws {
        try data.write(to: fileURL, options: .atomic)
    }

    func exists() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

/// Registers the `SpeakMCP` binary as an MCP server in Claude Code's settings.
enum ClaudeCodeMCPRegistration {
    /// Registers `SpeakMCP` in `~/.claude/settings.json` if not already correctly set.
    static func registerIfNeeded(
        fileAccess: SettingsFileAccessing = RealSettingsFileAccess(),
        binaryPath: String? = nil
    ) {
        let resolvedPath = binaryPath ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/SpeakMCP").path

        do {
            var settings: [String: Any]

            if fileAccess.exists() {
                let data = try fileAccess.read()
                if let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    settings = parsed
                } else {
                    // Malformed or non-dictionary JSON — start fresh
                    settings = [:]
                }
            } else {
                settings = [:]
            }

            // Get or create mcpServers dictionary
            var mcpServers = settings["mcpServers"] as? [String: Any] ?? [:]

            // Check if already correctly registered
            if let speak = mcpServers["speak"] as? [String: Any],
               speak["command"] as? String == resolvedPath {
                return // Already correct — no-op
            }

            // Add/update the speak entry
            mcpServers["speak"] = ["command": resolvedPath]
            settings["mcpServers"] = mcpServers

            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )

            try fileAccess.ensureDirectoryExists()
            try fileAccess.write(data)
        } catch {
            // Log but don't crash — MCP registration is best-effort
            print("ClaudeCodeMCPRegistration: failed to register — \(error)")
        }
    }
}
