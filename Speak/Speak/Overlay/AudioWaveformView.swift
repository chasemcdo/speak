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
        HStack(spacing: spacing) {
            ForEach(0 ..< barCount, id: \.self) { index in
                let level = index < barLevels.count ? CGFloat(barLevels[index]) : 0
                let normalized = min(level / 0.015, 1.0)
                let scaled = normalized * barScales[index]
                let height = minHeight + scaled * (maxHeight - minHeight)

                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(.blue)
                    .frame(width: barWidth, height: height)
            }
        }
        .animation(.easeOut(duration: 0.08), value: barLevels)
        .frame(height: maxHeight)
    }
}
