import SwiftUI

struct HistoryDetailView: View {
    let entry: HistoryEntry

    @State private var showingRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Processed text
                Text(entry.processedText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Metadata
                LabeledContent("Time") {
                    Text(entry.timestamp, format: .dateTime)
                }
                if let appName = entry.sourceAppName {
                    LabeledContent("Source App") {
                        Text(appName)
                    }
                }

                // Raw text (only when it differs)
                if entry.rawText != entry.processedText {
                    DisclosureGroup("Raw transcription", isExpanded: $showingRaw) {
                        Text(entry.rawText)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.processedText, forType: .string)
                }
            }
        }
    }
}
