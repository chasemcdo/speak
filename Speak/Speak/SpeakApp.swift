import SwiftUI

@main
struct SpeakApp: App {
    @State private var appState = AppState()
    @State private var coordinator = AppCoordinator()
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(\.openWindow) private var openWindow

    init() {
        UserDefaults.standard.register(defaults: [
            "autoPaste": true
        ])
    }

    var body: some Scene {
        MenuBarExtra("Speak", systemImage: appState.isRecording ? "mic.fill" : "mic") {
            MenuBarView()
                .environment(appState)
                .environment(coordinator)
                .onAppear {
                    coordinator.setUp(appState: appState)

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
            SettingsView()
                .environment(appState)
        }

        Window("Welcome to Speak", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
