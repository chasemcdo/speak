import SwiftUI

struct OverlayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isPreviewing {
                previewContent
            } else {
                recordingContent
            }
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

    private var recordingContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator
            if appState.isPostProcessing {
                ProcessingIndicator()
                    .padding(.top, 4)
            } else if let monitor = appState.audioLevel {
                AudioWaveformView(barLevels: monitor.barLevels)
                    .padding(.top, 4)
            } else {
                RecordingDot()
                    .padding(.top, 4)
            }

            // Transcription text
            VStack(alignment: .leading, spacing: 4) {
                if let error = appState.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.body)
                } else if appState.isPostProcessing {
                    Text("Formatting...")
                        .foregroundStyle(.secondary)
                        .font(.body)
                } else if appState.hasText {
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
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.previewText.isEmpty {
                Text("No text captured")
                    .foregroundStyle(.secondary)
                    .font(.body)
            } else {
                Text(appState.previewText)
                    .font(.body)
                    .lineLimit(8)
            }

            HStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(name: .overlayConfirmRequested, object: nil)
                } label: {
                    Text("Paste")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.previewText.isEmpty)

                Button {
                    NotificationCenter.default.post(name: .overlayCancelRequested, object: nil)
                } label: {
                    Text("Dismiss")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text(appState.previewText.isEmpty
                    ? "\u{238B} dismiss"
                    : "\u{23CE} paste  \u{238B} dismiss")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var transcriptionText: some View {
        Text("\(Text(appState.finalizedText).foregroundStyle(.primary))\(Text(appState.volatileText).foregroundStyle(.secondary))")
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

// MARK: - Processing indicator

struct ProcessingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "text.badge.checkmark")
            .foregroundStyle(.blue)
            .font(.system(size: 10))
            .opacity(isAnimating ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
