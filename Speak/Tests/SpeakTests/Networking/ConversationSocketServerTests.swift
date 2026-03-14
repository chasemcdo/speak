@testable import Speak
import Testing

@Suite(.serialized)
struct ConversationSocketServerTests {
    @Test @MainActor
    func `server starts and stops without crash`() {
        let server = ConversationSocketServer()
        server.start()
        server.stop()
    }

    @Test @MainActor
    func `server can start twice without crash`() {
        let server = ConversationSocketServer()
        server.start()
        server.start() // Should handle gracefully
        server.stop()
    }

    @Test @MainActor
    func `server stop without start is safe`() {
        let server = ConversationSocketServer()
        server.stop()
    }

    @Test @MainActor
    func `message struct stores action and text`() {
        let message = ConversationSocketServer.Message(action: "speak", text: "Hello")
        #expect(message.action == "speak")
        #expect(message.text == "Hello")
    }
}
