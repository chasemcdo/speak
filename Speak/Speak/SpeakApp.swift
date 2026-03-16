import Sparkle
import SwiftUI

@main
struct SpeakApp: App {
    @State private var appState = AppState()
    @State private var audioDeviceManager: AudioDeviceManager
    @State private var coordinator: AppCoordinator
    @State private var conversationCoordinator = ConversationCoordinator()
    @State private var historyStore = HistoryStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var showMCPSetupAlert = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    let updaterController: SPUStandardUpdaterController? = {
        #if DEBUG
            return nil
        #else
            return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }()

    init() {
        UserDefaults.standard.register(defaults: [
            "autoPaste": true,
            "removeFillerWords": true,
            "autoFormat": true,
            "llmRewrite": false,
        ])
        let deviceManager = AudioDeviceManager()
        _audioDeviceManager = State(initialValue: deviceManager)
        _coordinator = State(initialValue: AppCoordinator(audioDeviceManager: deviceManager))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(updater: updaterController?.updater)
                .environment(appState)
                .environment(coordinator)
                .environment(historyStore)
        } label: {
            Image("MenuBarIcon", bundle: .appModule)
                .alert(
                    "Conversation Mode Requires Setup",
                    isPresented: $showMCPSetupAlert
                ) {
                    Button("Open Settings") { openSettings() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "Connect Speak to Claude Code in Settings → Conversation Mode to use this feature."
                    )
                }
                .task {
                    conversationCoordinator.setUp(appState: appState)
                    conversationCoordinator.onSetupRequired = {
                        showMCPSetupAlert = true
                    }
                    conversationCoordinator.onConversationModeChanged = { [coordinator] active in
                        coordinator.setConversationMode(active)
                    }
                    coordinator.setUp(
                        appState: appState,
                        historyStore: historyStore,
                        onConversationToggle: { [conversationCoordinator] in
                            Task { @MainActor in
                                await conversationCoordinator.toggle()
                            }
                        }
                    )

                    // Let scene registration complete before opening windows
                    try? await Task.sleep(for: .milliseconds(200))

                    if !onboardingComplete {
                        openWindow(id: "onboarding")
                    } else {
                        // Check if permissions were lost (e.g., after system update
                        // or manual revocation in System Settings). Show a lightweight
                        // recovery view instead of resetting onboarding.
                        let hasAllPermissions = AudioCaptureManager.permissionGranted
                            && PasteService.accessibilityGranted
                            && ModelManager.authorizationGranted
                        if !hasAllPermissions {
                            openWindow(id: "permission-recovery")
                        }

                        if hasAllPermissions {
                            coordinator.preloadModel()
                        }
                    }
                }
        }

        Settings {
            SettingsView(updater: updaterController?.updater)
                .environment(appState)
                .environment(coordinator)
                .environment(audioDeviceManager)
        }

        Window("Welcome to Speak", id: "onboarding") {
            OnboardingView()
                .environment(appState)
                .environment(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Permissions", id: "permission-recovery") {
            PermissionRecoveryView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("History", id: "history") {
            HistoryView()
                .environment(historyStore)
        }
    }
}
