import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    @State private var micGranted = AudioCaptureManager.permissionGranted
    @State private var accessibilityGranted = PasteService.accessibilityGranted
    @State private var speechGranted = ModelManager.authorizationGranted

    var allGranted: Bool {
        micGranted && accessibilityGranted && speechGranted
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Welcome to Speak")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Speak needs a few permissions to work.\nAll processing happens on-device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Permission steps
            VStack(spacing: 16) {
                PermissionStep(
                    number: 1,
                    title: "Microphone",
                    description: "To hear your voice",
                    granted: micGranted
                ) {
                    await requestMicrophone()
                }

                PermissionStep(
                    number: 2,
                    title: "Speech Recognition",
                    description: "To transcribe your voice on-device",
                    granted: speechGranted
                ) {
                    await requestSpeech()
                }

                PermissionStep(
                    number: 3,
                    title: "Accessibility",
                    description: "To paste text into other apps",
                    granted: accessibilityGranted
                ) {
                    requestAccessibility()
                }
            }

            // Done button
            if allGranted {
                Button("Get Started") {
                    onboardingComplete = true
                    dismissWindow(id: "onboarding")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Grant all permissions above to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 400)
        .task {
            // Poll for permission changes (e.g., user grants via System Settings
            // or the callback arrives after the initial check)
            while !allGranted && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                micGranted = AudioCaptureManager.permissionGranted
                speechGranted = ModelManager.authorizationGranted
                accessibilityGranted = PasteService.accessibilityGranted
            }
        }
    }

    private func requestMicrophone() async {
        let manager = AudioCaptureManager()
        micGranted = await manager.requestPermission()
    }

    private func requestSpeech() async {
        let manager = ModelManager()
        speechGranted = await manager.requestAuthorization()
    }

    private func requestAccessibility() {
        PasteService.promptForAccessibility()
    }
}

// MARK: - Permission step row

struct PermissionStep: View {
    let number: Int
    let title: String
    let description: String
    let granted: Bool
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Number badge
            ZStack {
                Circle()
                    .fill(granted ? .green : .blue)
                    .frame(width: 28, height: 28)
                if granted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action
            if !granted {
                Button("Enable") {
                    Task { await action() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
