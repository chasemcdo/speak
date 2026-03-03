import SwiftUI

struct AudioWaveformView: View {
    var barLevels: [Float]

    private let barCount = 5
    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 1.5
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 14

    /// Bell curve envelope: center bar tallest, edges shorter
    private let barScales: [CGFloat] = [0.5, 0.8, 1.0, 0.8, 0.5]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: spacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    let level = index < barLevels.count ? CGFloat(barLevels[index]) : 0
                    let normalized = min(level / 0.015, 1.0)
                    let scaled = normalized * barScales[index]

                    // Per-bar sine shimmer: ~1.3 Hz, phase offset of 2π/5 between bars
                    let phase = time * 8.0 + Double(index) * (.pi * 2.0 / 5.0)
                    let shimmer = (1.0 - 0.12 * sin(phase)) * Double(scaled)

                    let height = minHeight + CGFloat(shimmer) * (maxHeight - minHeight)
                    let opacity = 1.0 - 0.15 * sin(phase) * Double(scaled)

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(.blue)
                        .opacity(opacity)
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(height: maxHeight)
        }
    }
}
