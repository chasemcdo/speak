import Foundation
import Network

/// Unix domain socket server for receiving MCP speak requests from the SpeakMCP process.
@MainActor
final class ConversationSocketServer {
    /// Message received from the MCP server.
    struct Message {
        let action: String
        let text: String
    }

    /// Callback fired when a speak message is received. The callback should return
    /// when TTS is complete so the server can send the acknowledgement.
    var onMessage: ((Message) async -> Void)?

    private var listener: NWListener?
    private var activeConnection: NWConnection?

    private nonisolated static var socketURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Speak")
        return appSupport.appendingPathComponent("conversation.sock")
    }

    func start() {
        let socketPath = Self.socketURL.path

        // Ensure directory exists
        let dir = Self.socketURL.deletingLastPathComponent().path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Remove stale socket
        unlink(socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

        do {
            listener = try NWListener(using: params)
        } catch {
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { _ in }

        listener?.start(queue: .main)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        unlink(Self.socketURL.path)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        activeConnection = connection

        connection.start(queue: .main)
        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }

                if let data = content, !data.isEmpty {
                    self.processData(data, on: connection)
                }

                if isComplete || error != nil {
                    connection.cancel()
                    if self.activeConnection === connection {
                        self.activeConnection = nil
                    }
                } else {
                    self.receiveData(on: connection)
                }
            }
        }
    }

    private func processData(_ data: Data, on connection: NWConnection) {
        guard let string = String(data: data, encoding: .utf8) else { return }

        // Parse newline-delimited JSON
        for line in string.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let action = json["action"] as? String,
                  let text = json["text"] as? String else {
                continue
            }

            let message = Message(action: action, text: text)

            Task { @MainActor [weak self] in
                await self?.onMessage?(message)

                // Send acknowledgement
                let ack: [String: Any] = ["status": "done"]
                if let ackData = try? JSONSerialization.data(withJSONObject: ack) {
                    connection.send(content: ackData, completion: .contentProcessed { _ in })
                }
            }
        }
    }

    deinit {
        unlink(Self.socketURL.path)
    }
}
