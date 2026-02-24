import Testing
import Foundation
@testable import Speak

@Suite("HistoryEntry")
struct HistoryEntryTests {

    @Test func codableRoundTrip() throws {
        let entry = HistoryEntry(
            rawText: "um hello world",
            processedText: "Hello world",
            sourceAppName: "Slack",
            sourceAppBundleID: "com.tinyspeck.slackmacgap"
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

    @Test func codableRoundTripWithNilOptionals() throws {
        let entry = HistoryEntry(
            rawText: "test",
            processedText: "Test"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)

        #expect(decoded.id == entry.id)
        #expect(decoded.rawText == "test")
        #expect(decoded.processedText == "Test")
        #expect(decoded.sourceAppName == nil)
        #expect(decoded.sourceAppBundleID == nil)
    }

    @Test func uniqueIdsGenerated() {
        let a = HistoryEntry(rawText: "a", processedText: "A")
        let b = HistoryEntry(rawText: "b", processedText: "B")
        #expect(a.id != b.id)
    }
}
