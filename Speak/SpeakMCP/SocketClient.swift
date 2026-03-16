import Foundation

/// Connects to the Speak app's Unix domain socket to send speak requests.
final class SocketClient {
    private let socketPath: String

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Speak")
        socketPath = appSupport.appendingPathComponent("conversation.sock").path
    }

    /// Send text to the Speak app and wait for acknowledgement.
    /// Returns `true` if the Speak app confirmed TTS completion.
    func sendAndWait(text: String, timeout: TimeInterval = 60) -> Bool {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Prevent SIGPIPE on broken connections
        var noSigPipe: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

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
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        // Send speak request as newline-delimited JSON
        let request: [String: Any] = ["action": "speak", "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              var message = String(data: data, encoding: .utf8) else { return false }
        message += "\n"

        // Send all bytes, handling partial writes
        guard sendAll(socketFD: sock, message: message) else { return false }

        // Set receive timeout
        var recvTimeout = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))

        // Read until newline delimiter (matching server's framing)
        guard let responseData = recvUntilNewline(socketFD: sock) else { return false }

        guard let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let status = response["status"] as? String else { return false }

        return status == "done"
    }

    // MARK: - Helpers

    /// Send all bytes from a message, retrying on partial writes.
    private func sendAll(socketFD: Int32, message: String) -> Bool {
        let messageData = Array(message.utf8)
        var totalSent = 0

        while totalSent < messageData.count {
            let remaining = messageData.count - totalSent
            let sent = messageData.withUnsafeBufferPointer { buf in
                send(socketFD, buf.baseAddress! + totalSent, remaining, 0)
            }

            if sent > 0 {
                totalSent += sent
            } else if sent == 0 {
                return false // Connection closed
            } else {
                if errno == EINTR { continue }
                return false // Fatal error
            }
        }
        return true
    }

    /// Read from the socket until a newline is found, returning the data before the newline.
    private func recvUntilNewline(socketFD: Int32) -> Data? {
        var accumulated = Data()
        var byte: UInt8 = 0

        while true {
            let result = recv(socketFD, &byte, 1, 0)
            if result == 1 {
                if byte == UInt8(ascii: "\n") {
                    return accumulated
                }
                accumulated.append(byte)

                // Safety limit — prevent unbounded reads
                if accumulated.count > 65536 { return nil }
            } else if result == 0 {
                // Connection closed — return what we have if non-empty
                return accumulated.isEmpty ? nil : accumulated
            } else {
                if errno == EINTR { continue }
                return nil
            }
        }
    }
}
