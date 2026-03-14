import Foundation

/// Connects to the Speak app's Unix domain socket to send speak requests.
final class SocketClient {
    private let socketPath: String

    init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Speak")
        socketPath = appSupport.appendingPathComponent("conversation.sock").path
    }

    /// Send text to the Speak app and wait for acknowledgement.
    /// Returns `true` if the Speak app confirmed TTS completion.
    func sendAndWait(text: String, timeout: TimeInterval = 60) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        // Send speak request as newline-delimited JSON
        let request: [String: Any] = ["action": "speak", "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              var message = String(data: data, encoding: .utf8) else { return false }
        message += "\n"

        let sent = message.withCString { ptr in
            send(fd, ptr, strlen(ptr), 0)
        }
        guard sent > 0 else { return false }

        // Set receive timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Wait for response
        var buffer = [CChar](repeating: 0, count: 4096)
        let received = recv(fd, &buffer, buffer.count - 1, 0)
        guard received > 0 else { return false }

        buffer[received] = 0
        guard let responseString = String(cString: buffer, encoding: .utf8),
              let responseData = responseString.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let status = response["status"] as? String else { return false }

        return status == "done"
    }
}
