import Foundation

/// A minimal MCP (Model Context Protocol) server that exposes a `speak` tool.
/// Communicates with the Speak app via Unix domain socket.
final class MCPServer {
    private let socketClient = SocketClient()

    func run() {
        // Read JSON-RPC requests from stdin, write responses to stdout
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                writeError(id: nil, code: -32700, message: "Parse error")
                continue
            }

            let id = request["id"]
            let method = request["method"] as? String

            switch method {
            case "initialize":
                handleInitialize(id: id)
            case "notifications/initialized":
                // Client acknowledgement — no response needed
                break
            case "tools/list":
                handleToolsList(id: id)
            case "tools/call":
                handleToolsCall(id: id, params: request["params"] as? [String: Any])
            default:
                writeError(id: id, code: -32601, message: "Method not found: \(method ?? "nil")")
            }
        }
    }

    // MARK: - Handlers

    private func handleInitialize(id: Any?) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id as Any,
            "result": [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [String: Any](),
                ],
                "serverInfo": [
                    "name": "speak",
                    "version": "1.0.0",
                ],
            ] as [String: Any],
        ]
        writeJSON(response)
    }

    private func handleToolsList(id: Any?) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id as Any,
            "result": [
                "tools": [
                    [
                        "name": "speak",
                        "description": "Speak a response aloud to the user via text-to-speech. The user is listening, not reading — keep responses concise and conversational (1-3 sentences). Use this to communicate results, ask clarifying questions, or summarize what you did.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "text": [
                                    "type": "string",
                                    "description": "Text to speak aloud",
                                ] as [String: Any],
                            ],
                            "required": ["text"],
                        ] as [String: Any],
                    ] as [String: Any],
                ],
            ] as [String: Any],
        ]
        writeJSON(response)
    }

    private func handleToolsCall(id: Any?, params: [String: Any]?) {
        guard let params,
              let name = params["name"] as? String,
              name == "speak",
              let arguments = params["arguments"] as? [String: Any],
              let text = arguments["text"] as? String else {
            writeError(
                id: id,
                code: -32602,
                message: "Invalid params: expected {name: 'speak', arguments: {text: string}}"
            )
            return
        }

        // Send text to Speak app via socket and wait for completion
        let success = socketClient.sendAndWait(text: text)

        let content: [[String: Any]] = [
            [
                "type": "text",
                "text": success ? "Spoke: \(text)" : "Failed to speak — Speak app may not be in conversation mode.",
            ],
        ]

        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id as Any,
            "result": [
                "content": content,
                "isError": !success,
            ] as [String: Any],
        ]
        writeJSON(response)
    }

    // MARK: - Output

    private func writeJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        print(string)
        fflush(stdout)
    }

    private func writeError(id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id as Any,
            "error": [
                "code": code,
                "message": message,
            ] as [String: Any],
        ]
        writeJSON(response)
    }
}
