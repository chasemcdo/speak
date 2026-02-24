import SwiftUI
import Sparkle

@main
struct SpeakApp: App {
    @State private var appState = AppState()
    @State private var coordinator = AppCoordinator()
    @State private var historyStore = HistoryStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var needsPermissionRecovery = false
    @Environment(\.openWindow) private var openWindow

    let updaterController: SPUStandardUpdaterController? = {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    init() {
        UserDefaults.standard.register(defaults: [
            "autoPaste": true,
            "removeFillerWords": true,
            "autoFormat": true,
            "llmRewrite": false,
        ])
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(updater: updaterController?.updater)
                .environment(appState)
                .environment(coordinator)
                .environment(historyStore)
        } label: {
            Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                .task {
                    coordinator.setUp(appState: appState, historyStore: historyStore)

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
                            needsPermissionRecovery = true
                            openWindow(id: "permission-recovery")
                        }

                        coordinator.preloadModel()
                    }
                }
        }

        Settings {
            SettingsView(updater: updaterController?.updater)
                .environment(appState)
        }

        Window("Welcome to Speak", id: "onboarding") {
            OnboardingView()
                .environment(appState)
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
