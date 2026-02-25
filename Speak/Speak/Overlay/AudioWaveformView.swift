import SwiftUI

struct AudioWaveformView: View {
    var barLevels: [Float]

    private let barCount = 5
    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 1.5
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 14

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < barLevels.count ? CGFloat(barLevels[index]) : 0
                // Map RMS level (typically 0.0–0.3) to bar height
                let normalized = min(level / 0.15, 1.0)
                let height = minHeight + normalized * (maxHeight - minHeight)

                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(.red)
                    .frame(width: barWidth, height: height)
            }
        }
        .animation(.easeOut(duration: 0.08), value: barLevels)
        .frame(height: maxHeight)
    }
}
