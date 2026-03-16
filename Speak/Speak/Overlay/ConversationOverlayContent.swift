import SwiftUI

/// Overlay content shown during conversation mode, with phase-specific visuals.
struct ConversationOverlayContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            phaseIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                phaseText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch appState.conversationPhase {
        case .listening, .transcribing:
            if let monitor = appState.audioLevel {
                AudioWaveformView(barLevels: monitor.barLevels)
            } else {
                RecordingDot()
            }
        case .submitting:
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 12))
        case .waitingForClaude:
            ThinkingIndicator()
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 12))
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var phaseText: some View {
        switch appState.conversationPhase {
        case .listening:
            if appState.hasText {
                transcriptionText
            } else {
                Text("Listening...")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
        case .transcribing:
            transcriptionText
        case .submitting:
            Text("Sending to Claude...")
                .foregroundStyle(.secondary)
                .font(.body)
        case .waitingForClaude:
            Text("Waiting for Claude...")
                .foregroundStyle(.secondary)
                .font(.body)
        case .speaking:
            Text(appState.claudeResponseText)
                .font(.body)
                .lineLimit(8)
        case .idle:
            EmptyView()
        }
    }

    private var transcriptionText: some View {
        Text(
            "\(Text(appState.finalizedText).foregroundStyle(.primary))\(Text(appState.volatileText).foregroundStyle(.secondary))"
        )
        .font(.body)
        .lineLimit(8)
    }
}

// MARK: - Thinking indicator

struct ThinkingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "brain")
            .foregroundStyle(.purple)
            .font(.system(size: 12))
            .opacity(isAnimating ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
