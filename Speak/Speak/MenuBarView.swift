import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator

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
                Button("Start Dictation (fn fn)") {
                    Task { await coordinator.start() }
                }
            }

            Divider()

            if let error = appState.error {
                Text(error)
                    .foregroundStyle(.red)
                Divider()
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
