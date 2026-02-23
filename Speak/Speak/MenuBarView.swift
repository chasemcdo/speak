import SwiftUI
import Sparkle

struct MenuBarView: View {
    let updater: SPUUpdater
    @Environment(AppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(HistoryStore.self) private var historyStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hotkeyModifier") private var hotkey: TranscriptionHotkey = .fn

    var body: some View {
        Group {
            if appState.isRecording {
                Button("Stop Dictation") {
                    Task { await coordinator.confirm() }
                }
                .keyboardShortcut(.return)

                Button("Cancel") {
                    Task { await coordinator.cancel() }
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
                        Text(entry.processedText)
                            .lineLimit(1)
                    }
                }

                Button("Show All History...") {
                    openWindow(id: "history")
                }

                Divider()
            }

            CheckForUpdatesView(updater: updater)

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
