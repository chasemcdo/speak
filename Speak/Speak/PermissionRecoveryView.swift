import SwiftUI

/// Lightweight view shown when an already-onboarded user has lost permissions
/// (e.g., after a system update or manual revocation in System Settings).
/// Only shows the permissions that are actually missing.
struct PermissionRecoveryView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var micGranted = AudioCaptureManager.permissionGranted
    @State private var accessibilityGranted = PasteService.accessibilityGranted
    @State private var speechGranted = ModelManager.authorizationGranted
    @State private var canRequestMic = AudioCaptureManager.permissionNotDetermined
    @State private var canRequestSpeech = ModelManager.authorizationNotDetermined

    private var allGranted: Bool {
        micGranted && accessibilityGranted && speechGranted
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                Text("Permissions Needed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Some permissions need to be re-enabled.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Only show missing permissions
            VStack(spacing: 12) {
                if !micGranted {
                    PermissionRecoveryRow(
                        title: "Microphone",
                        description: "Required to hear your voice",
                        canRequestDirectly: canRequestMic,
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    ) {
                        let manager = AudioCaptureManager()
                        micGranted = await manager.requestPermission()
                        canRequestMic = AudioCaptureManager.permissionNotDetermined
                    }
                }

                if !speechGranted {
                    PermissionRecoveryRow(
                        title: "Speech Recognition",
                        description: "Required for on-device transcription",
                        canRequestDirectly: canRequestSpeech,
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                    ) {
                        let manager = ModelManager()
                        speechGranted = await manager.requestAuthorization()
                        canRequestSpeech = ModelManager.authorizationNotDetermined
                    }
                }

                if !accessibilityGranted {
                    PermissionRecoveryRow(
                        title: "Accessibility",
                        description: "Required to paste text into other apps",
                        canRequestDirectly: false,
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    ) { }
                }
            }

            if !allGranted {
                Text("Grant the permissions above to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 400)
        .task {
            // Poll for permission restoration
            while !allGranted && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                micGranted = AudioCaptureManager.permissionGranted
                accessibilityGranted = PasteService.accessibilityGranted
                speechGranted = ModelManager.authorizationGranted
            }
            if allGranted {
                dismissWindow(id: "permission-recovery")
            }
        }
    }
}

// MARK: - Permission recovery row

private struct PermissionRecoveryRow: View {
    let title: String
    let description: String
    let canRequestDirectly: Bool
    let settingsURL: String
    let requestAction: @MainActor () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if canRequestDirectly {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
