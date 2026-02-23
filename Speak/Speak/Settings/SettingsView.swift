import SwiftUI
import Speech
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("locale") private var localeIdentifier = Locale.current.identifier
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("hotkeyModifier") private var hotkey: TranscriptionHotkey = .fn
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var supportedLocales: [Locale] = []
    @State private var micGranted = AudioCaptureManager.permissionGranted
    @State private var accessibilityGranted = PasteService.accessibilityGranted
    @State private var speechGranted = ModelManager.authorizationGranted

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Language", selection: $localeIdentifier) {
                    if supportedLocales.isEmpty {
                        Text("Loading...").tag(localeIdentifier)
                    } else {
                        ForEach(supportedLocales, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale.identifier)
                        }
                    }
                }

                Toggle("Auto-paste into active app", isOn: $autoPaste)
                    .help("When enabled, text is automatically pasted into the focused app. When disabled, text is copied to the clipboard.")
            }

            Section("Hotkey") {
                Picker("Toggle dictation", selection: $hotkey) {
                    ForEach(TranscriptionHotkey.allCases, id: \.self) { key in
                        Text(key.label).tag(key)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    granted: micGranted,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
                PermissionRow(
                    title: "Accessibility",
                    granted: accessibilityGranted,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                PermissionRow(
                    title: "Speech Recognition",
                    granted: speechGranted,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
        .task {
            await loadSupportedLocales()
        }
        .task {
            // Poll for permission changes (e.g., user grants access via System Settings)
            while !Task.isCancelled {
                micGranted = AudioCaptureManager.permissionGranted
                accessibilityGranted = PasteService.accessibilityGranted
                speechGranted = ModelManager.authorizationGranted
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func loadSupportedLocales() async {
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocales = locales.sorted {
            let name0 = $0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
            let name1 = $1.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
            return name0 < name1
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail — user can manage this in System Settings
        }
    }
}

// MARK: - Permission row

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let settingsURL: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
