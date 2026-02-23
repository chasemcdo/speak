import SwiftUI
import Sparkle

@main
struct SpeakApp: App {
    @State private var appState = AppState()
    @State private var coordinator = AppCoordinator()
    @State private var historyStore = HistoryStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(\.openWindow) private var openWindow

    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        UserDefaults.standard.register(defaults: [
            "autoPaste": true,
            "removeFillerWords": true,
            "autoFormat": true,
            "llmRewrite": false,
        ])
    }

    var body: some Scene {
        MenuBarExtra("Speak", systemImage: appState.isRecording ? "mic.fill" : "mic") {
            MenuBarView(updater: updaterController.updater)
                .environment(appState)
                .environment(coordinator)
                .environment(historyStore)
                .onAppear {
                    coordinator.setUp(appState: appState, historyStore: historyStore)

                    // If permissions were revoked (e.g., after Xcode rebuild),
                    // reset onboarding so the user is prompted to re-grant them.
                    if onboardingComplete {
                        let hasAllPermissions = AudioCaptureManager.permissionGranted
                            && PasteService.accessibilityGranted
                            && ModelManager.authorizationGranted
                        if !hasAllPermissions {
                            onboardingComplete = false
                        }
                    }

                    if !onboardingComplete {
                        openWindow(id: "onboarding")
                    }

                    // Pre-download the speech model so it's ready when the
                    // user starts their first recording.
                    if onboardingComplete {
                        coordinator.preloadModel()
                    }
                }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(appState)
        }

        Window("Welcome to Speak", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("History", id: "history") {
            HistoryView()
                .environment(historyStore)
        }
    }
}
