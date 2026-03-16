import Foundation

/// Checks whether the `SpeakMCP` binary is registered as an MCP server in Claude Code's settings.
enum ClaudeCodeMCPRegistration {
    /// The `claude mcp add` command users should run to register the server.
    static func setupCommand(binaryPath: String? = nil) -> String {
        let path = binaryPath ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/SpeakMCP").path
        return "claude mcp add speak -s user -- \(path)"
    }

    /// Returns `true` if the speak MCP server is registered in `~/.claude/settings.json`.
    static func isRegistered(binaryPath: String? = nil) -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settingsURL),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let mcpServers = settings["mcpServers"] as? [String: Any],
              let speak = mcpServers["speak"] as? [String: Any],
              speak["command"] != nil else {
            return false
        }
        return true
    }
}
