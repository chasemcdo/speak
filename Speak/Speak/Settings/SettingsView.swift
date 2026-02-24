import SwiftUI
import Speech
import ServiceManagement
import FoundationModels
import Sparkle

struct SettingsView: View {
    let updater: SPUUpdater?
    @Environment(AppState.self) private var appState
    @AppStorage("locale") private var localeIdentifier = Locale.current.identifier
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("hotkeyModifier") private var hotkey: TranscriptionHotkey = .fn
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("removeFillerWords") private var removeFillerWords = true
    @AppStorage("autoFormat") private var autoFormat = true
    @AppStorage("llmRewrite") private var llmRewrite = false
    @AppStorage("screenContext") private var screenContext = false

    @State private var automaticallyChecksForUpdates = false
    @State private var automaticallyDownloadsUpdates = false

    @State private var supportedLocales: [Locale] = []
    @State private var micGranted = AudioCaptureManager.permissionGranted
    @State private var accessibilityGranted = PasteService.accessibilityGranted
    @State private var speechGranted = ModelManager.authorizationGranted

    private var llmAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

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

            Section("Post-Processing") {
                Toggle("Remove filler words", isOn: $removeFillerWords)
                    .help("Strip filler words like 'um', 'uh', 'like', 'you know' from transcribed text.")

                Toggle("Auto-format text", isOn: $autoFormat)
                    .help("Auto-capitalize sentences and clean up punctuation.")

                Toggle("AI-powered formatting", isOn: $llmRewrite)
                    .help("Use Apple Intelligence to clean up grammar, format lists, add paragraphs, and match your writing style.")
                    .disabled(!llmAvailable)

                Toggle("Screen context", isOn: $screenContext)
                    .help("Read names, filenames, and terms from your screen to correct spelling in dictated text.")
                    .disabled(!llmRewrite)

                if !llmAvailable {
                    Text("AI cleanup requires Apple Intelligence to be enabled in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

            if let updater {
                Section("Updates") {
                    Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                            updater.automaticallyChecksForUpdates = newValue
                        }
                    Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                        .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                            updater.automaticallyDownloadsUpdates = newValue
                        }
                }
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    granted: micGranted,
                    canRequestDirectly: AudioCaptureManager.permissionNotDetermined,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                ) {
                    let manager = AudioCaptureManager()
                    micGranted = await manager.requestPermission()
                }
                PermissionRow(
                    title: "Accessibility",
                    granted: accessibilityGranted,
                    canRequestDirectly: false,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) { }
                PermissionRow(
                    title: "Speech Recognition",
                    granted: speechGranted,
                    canRequestDirectly: ModelManager.authorizationNotDetermined,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                ) {
                    let manager = ModelManager()
                    speechGranted = await manager.requestAuthorization()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 520)
        .onAppear {
            if let updater {
                automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
                automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
            }
        }
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
    let canRequestDirectly: Bool
    let settingsURL: String
    let requestAction: @MainActor () async -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if canRequestDirectly {
                Button("Enable") {
                    Task { await requestAction() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Open Settings") {
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
