import SwiftUI
import Sparkle

struct MenuBarView: View {
    let updater: SPUUpdater?
    @Environment(AppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(HistoryStore.self) private var historyStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hotkeyModifier") private var hotkey: TranscriptionHotkey = .fn

    var body: some View {
        Group {
            if appState.isPreviewing {
                Button("Paste Transcription") {
                    Task { await coordinator.pasteFromPreview() }
                }
                .keyboardShortcut(.return)

                Button("Dismiss") {
                    coordinator.dismissPreview()
                }
                .keyboardShortcut(.escape)
            } else if appState.isRecording {
                Button("Stop Dictation") {
                    Task { await coordinator.confirm() }
                }
                .keyboardShortcut(.return)

                Button("Stop & Preview") {
                    Task { await coordinator.stopWithoutPaste() }
                }
                .keyboardShortcut(.escape)
            } else {
                Button("Start Dictation (\(hotkey.shortLabel) \(hotkey.shortLabel))") {
                    Task { await coordinator.start() }
                }
            }

            Divider()

            if let error = appState.error {
                Text(error)
                    .foregroundStyle(.red)
                Divider()
            }

            if !historyStore.entries.isEmpty {
                ForEach(historyStore.entries.prefix(5)) { entry in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.processedText, forType: .string)
                    } label: {
                        Text(entry.processedText.menuLabel)
                    }
                }

                Button("Show All History...") {
                    openWindow(id: "history")
                }

                Divider()
            }

            if let updater {
                CheckForUpdatesView(updater: updater)
            }

            SettingsLink {
                Text("Settings...")
            }

            Divider()

            Button("Quit Speak") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

private extension String {
    /// Single-line truncated label suitable for a menu item.
    var menuLabel: String {
        let flat = self.replacingOccurrences(of: "\n", with: " ")
        if flat.count <= 50 { return flat }
        return String(flat.prefix(50)) + "…"
    }
}
