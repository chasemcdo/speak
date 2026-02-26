import SwiftUI

struct DictionarySettingsView: View {
    @Environment(DictionaryStore.self) private var dictionaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newWord = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // MARK: - Add Word

                Section("Add Word") {
                    HStack {
                        TextField("Word or phrase", text: $newWord)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addWord() }
                        Button("Add") { addWord() }
                            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // MARK: - Suggestions

                if !dictionaryStore.suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(dictionaryStore.suggestions) { suggestion in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.phrase)
                                        .fontWeight(.semibold)
                                    Text("was transcribed as: \(suggestion.original)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Accept") {
                                    dictionaryStore.acceptSuggestion(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button("Dismiss") {
                                    dictionaryStore.dismissSuggestion(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // MARK: - Words

                Section("Words (\(dictionaryStore.entries.count))") {
                    if dictionaryStore.entries.isEmpty {
                        Text("No words added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dictionaryStore.entries) { entry in
                            HStack {
                                Text(entry.phrase)
                                Spacer()
                                Text(entry.source == .learned ? "Learned" : "Manual")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        entry.source == .learned
                                            ? Color.blue.opacity(0.15)
                                            : Color.gray.opacity(0.15)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                        .onDelete { offsets in
                            dictionaryStore.remove(at: offsets)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear All") {
                    dictionaryStore.clearAll()
                }
                .disabled(dictionaryStore.entries.isEmpty)
            }
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dictionaryStore.add(trimmed)
        newWord = ""
    }
}
