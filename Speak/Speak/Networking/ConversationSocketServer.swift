import Foundation
import Network

/// Shared socket path used by both the Speak app (server) and SpeakMCP (client).
enum ConversationSocket {
    static var url: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Speak")
        return appSupport.appendingPathComponent("conversation.sock")
    }
}

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
    /// Per-connection buffer for accumulating partial frames.
    private var receiveBuffer = Data()

    nonisolated private static var socketURL: URL {
        ConversationSocket.url
    }

    func start() {
        // Clean up any existing listener before rebinding
        stop()

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

        listener?.stateUpdateHandler = { state in
            if case .failed = state {
                MainActor.assumeIsolated { [weak self] in
                    self?.stop()
                }
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        receiveBuffer.removeAll()
        listener?.cancel()
        listener = nil
        unlink(Self.socketURL.path)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        activeConnection = connection
        receiveBuffer.removeAll()

        connection.start(queue: .main)
        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection
            .receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
                MainActor.assumeIsolated {
                    guard let self else { return }

                    if let data = content, !data.isEmpty {
                        self.receiveBuffer.append(data)
                        self.processBufferedFrames(on: connection)
                    }

                    if isComplete || error != nil {
                        connection.cancel()
                        if self.activeConnection === connection {
                            self.activeConnection = nil
                            self.receiveBuffer.removeAll()
                        }
                    } else {
                        self.receiveData(on: connection)
                    }
                }
            }
    }

    /// Extract and process complete newline-delimited frames from the buffer.
    private func processBufferedFrames(on connection: NWConnection) {
        let newline = UInt8(ascii: "\n")

        while let newlineIndex = receiveBuffer.firstIndex(of: newline) {
            let frameData = receiveBuffer[receiveBuffer.startIndex ..< newlineIndex]
            receiveBuffer = receiveBuffer[(newlineIndex + 1)...]

            guard let json = try? JSONSerialization.jsonObject(with: frameData) as? [String: Any],
                  let action = json["action"] as? String,
                  let text = json["text"] as? String else {
                continue
            }

            let message = Message(action: action, text: text)

            Task { @MainActor [weak self] in
                await self?.onMessage?(message)

                // Send newline-terminated acknowledgement
                let ack: [String: Any] = ["status": "done"]
                if let ackData = try? JSONSerialization.data(withJSONObject: ack) {
                    var payload = ackData
                    payload.append(newline)
                    connection.send(content: payload, completion: .contentProcessed { _ in })
                }
            }
        }
    }

    deinit {
        unlink(Self.socketURL.path)
    }
}
