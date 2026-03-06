import Foundation
@testable import Speak
import Testing

struct HistoryEntryTests {
    @Test func `codable round trip`() throws {
        let entry = HistoryEntry(
            rawText: "um hello world",
            processedText: "Hello world",
            sourceAppName: "Slack",
            sourceAppBundleID: "com.tinyspeck.slackmacgap",
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)

        #expect(decoded.id == entry.id)
        #expect(decoded.rawText == entry.rawText)
        #expect(decoded.processedText == entry.processedText)
        #expect(decoded.sourceAppName == entry.sourceAppName)
        #expect(decoded.sourceAppBundleID == entry.sourceAppBundleID)
        #expect(decoded.timestamp == entry.timestamp)
    }

    @Test func `codable round trip with nil optionals`() throws {
        let entry = HistoryEntry(
            rawText: "test",
            processedText: "Test",
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)

        #expect(decoded.id == entry.id)
        #expect(decoded.rawText == "test")
        #expect(decoded.processedText == "Test")
        #expect(decoded.sourceAppName == nil)
        #expect(decoded.sourceAppBundleID == nil)
    }

    @Test func `unique ids generated`() {
        let a = HistoryEntry(rawText: "a", processedText: "A")
        let b = HistoryEntry(rawText: "b", processedText: "B")
        #expect(a.id != b.id)
    }
}
