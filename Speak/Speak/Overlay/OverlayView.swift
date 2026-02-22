import SwiftUI

struct OverlayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Recording indicator
            RecordingDot()
                .padding(.top, 4)

            // Transcription text
            VStack(alignment: .leading, spacing: 4) {
                if appState.hasText {
                    transcriptionText
                } else if appState.isModelDownloading {
                    Text("Downloading speech model...")
                        .foregroundStyle(.secondary)
                        .font(.body)
                } else {
                    Text("Listening...")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var transcriptionText: some View {
        Group {
            Text(appState.finalizedText)
                .foregroundStyle(.primary) +
            Text(appState.volatileText)
                .foregroundStyle(.secondary)
        }
        .font(.body)
        .lineLimit(8)
    }
}

// MARK: - Recording dot

struct RecordingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
