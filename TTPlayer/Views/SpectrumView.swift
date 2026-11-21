import SwiftUI

/// 20 段柱状频谱：柱体渐变 + 顶部峰值钉，停播时自然回落。
struct SpectrumView: View {
    let bands: [Float]
    let peaks: [Float]
    let theme: Theme
    var barCount: Int = SpectrumAnalyzer.bandCount

    var body: some View {
        GeometryReader { geo in
            let count = max(1, barCount)
            let spacing: CGFloat = 2.4
            let available = max(1, geo.size.width - spacing * CGFloat(count - 1))
            let barWidth = max(1.2, available / CGFloat(count))
            let usableHeight = max(1, geo.size.height - 4)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let bandValue = index < bands.count ? CGFloat(bands[index]) : 0
                    let peakValue = index < peaks.count ? CGFloat(peaks[index]) : 0
                    let barHeight = max(1.5, usableHeight * min(1, max(0, bandValue)))
                    let peakOffset = usableHeight * min(1, max(0, peakValue))

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.3, style: .continuous)
                            .fill(theme.spectrumBottom.opacity(0.12))
                            .frame(width: barWidth, height: geo.size.height)
                        RoundedRectangle(cornerRadius: 1.3, style: .continuous)
                            .fill(theme.spectrumGradient)
                            .frame(width: barWidth, height: barHeight)
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(theme.spectrumPeak.opacity(0.85))
                            .frame(width: barWidth, height: 1.8)
                            .offset(y: -min(usableHeight - 1.8, max(0, peakOffset)))
                    }
                    .frame(width: barWidth, height: geo.size.height)
                }
            }
        }
    }
}
