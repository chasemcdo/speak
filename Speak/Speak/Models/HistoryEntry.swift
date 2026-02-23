import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var rawText: String
    var processedText: String
    var timestamp = Date()
    var sourceAppName: String?
    var sourceAppBundleID: String?
}
