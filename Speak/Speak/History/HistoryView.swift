import SwiftUI

struct HistoryView: View {
    @Environment(HistoryStore.self) private var historyStore
    @State private var selectedEntryID: UUID?
    @State private var searchText = ""

    private var filteredEntries: [HistoryEntry] {
        if searchText.isEmpty {
            return historyStore.entries
        }
        return historyStore.entries.filter {
            $0.processedText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredEntries, selection: $selectedEntryID) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.processedText)
                        .lineLimit(2)
                    HStack {
                        Text(entry.timestamp, style: .relative)
                            .foregroundStyle(.secondary)
                        if let appName = entry.sourceAppName {
                            Text("· \(appName)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 2)
            }
            .searchable(text: $searchText, prompt: "Search history")
            .toolbar {
                ToolbarItem {
                    Button("Clear All", role: .destructive) {
                        historyStore.clearAll()
                        selectedEntryID = nil
                    }
                    .disabled(historyStore.entries.isEmpty)
                }
            }
            .overlay {
                if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .opacity(searchText.isEmpty ? 0 : 1)
                }
            }
        } detail: {
            if let id = selectedEntryID,
               let entry = historyStore.entries.first(where: { $0.id == id }) {
                HistoryDetailView(entry: entry)
            } else {
                ContentUnavailableView("Select an entry", systemImage: "text.quote")
            }
        }
        .navigationTitle("History")
    }
}
