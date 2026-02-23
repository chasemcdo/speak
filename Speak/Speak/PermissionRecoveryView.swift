import SwiftUI

/// Lightweight view shown when an already-onboarded user has lost permissions
/// (e.g., after a system update or manual revocation in System Settings).
/// Only shows the permissions that are actually missing.
struct PermissionRecoveryView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var micGranted = AudioCaptureManager.permissionGranted
    @State private var accessibilityGranted = PasteService.accessibilityGranted
    @State private var speechGranted = ModelManager.authorizationGranted

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

                Text("Some permissions need to be re-enabled.\nOpen System Settings to restore them.")
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
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )
                }

                if !speechGranted {
                    PermissionRecoveryRow(
                        title: "Speech Recognition",
                        description: "Required for on-device transcription",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                    )
                }

                if !accessibilityGranted {
                    PermissionRecoveryRow(
                        title: "Accessibility",
                        description: "Required to paste text into other apps",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    )
                }
            }

            // Continue button appears when all permissions are restored
            if allGranted {
                Button("Continue") {
                    dismissWindow(id: "permission-recovery")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Re-enable the permissions above to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 400)
        .task {
            // Poll for permission restoration
            while !allGranted {
                try? await Task.sleep(for: .seconds(1))
                micGranted = AudioCaptureManager.permissionGranted
                accessibilityGranted = PasteService.accessibilityGranted
                speechGranted = ModelManager.authorizationGranted
            }
        }
    }
}

// MARK: - Permission recovery row

private struct PermissionRecoveryRow: View {
    let title: String
    let description: String
    let settingsURL: String

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

            Button("Open Settings") {
                if let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
