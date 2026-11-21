import SwiftUI

/// 经典频谱：24 段柱体，柱身辉光渐变、下方镜面倒影、峰值钉悬浮回落。
struct SpectrumView: View {
    let bands: [Float]
    let peaks: [Float]
    let theme: Theme
    var barCount: Int = SpectrumAnalyzer.bandCount
    var showsMirror: Bool = true

    var body: some View {
        GeometryReader { geo in
            let count = max(1, barCount)
            let width = max(1, geo.size.width)
            let height = max(1, geo.size.height)
            let gap = max(1.1, width * 0.008)
            let barWidth = max(1, (width - gap * CGFloat(count - 1)) / CGFloat(count))
            let reflection = showsMirror ? height * 0.24 : 0
            let barArea = max(1, height - reflection - (showsMirror ? 3 : 0))

            VStack(spacing: showsMirror ? 3 : 0) {
                barStack(count: count, barWidth: barWidth, height: barArea, gap: gap)
                    .frame(height: barArea, alignment: .bottom)

                if showsMirror {
                    mirrorStack(count: count, barWidth: barWidth, height: reflection, gap: gap)
                        .frame(height: reflection, alignment: .top)
                        .mask(
                            LinearGradient(
                                colors: [Color.black.opacity(0.55), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
    }

    // MARK: 柱体

    private func barStack(count: Int, barWidth: CGFloat, height: CGFloat, gap: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<count, id: \.self) { index in
                let value = level(bands, index)
                let peak = level(peaks, index)
                let barHeight = max(1.5, height * value)
                let peakOffset = min(height - 1.6, max(0, height * peak - 1.6))

                ZStack(alignment: .bottom) {
                    // 淡淡的整格底槽，静音时也能看出 24 段
                    RoundedRectangle(cornerRadius: barWidth * 0.45, style: .continuous)
                        .fill(theme.spectrumBottom.opacity(0.10))
                        .frame(width: barWidth, height: height)

                    RoundedRectangle(cornerRadius: barWidth * 0.45, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    theme.spectrumTop,
                                    theme.spectrumTop.opacity(0.75),
                                    theme.spectrumBottom
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: barHeight)
                        .shadow(color: theme.spectrumTop.opacity(0.45), radius: 3, x: 0, y: 0)

                    // 左侧高光，柱体看起来是亮面玻璃
                    RoundedRectangle(cornerRadius: barWidth * 0.3, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: max(0.8, barWidth * 0.26), height: max(1, barHeight - 2))
                        .offset(x: -barWidth * 0.24, y: -1)

                    // 峰值钉
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(theme.spectrumPeak.opacity(0.92))
                        .frame(width: barWidth, height: 1.6)
                        .shadow(color: theme.spectrumPeak.opacity(0.75), radius: 2.5, x: 0, y: 0)
                        .offset(y: -peakOffset)
                }
                .frame(width: barWidth, height: height, alignment: .bottom)
            }
        }
    }

    // MARK: 倒影

    private func mirrorStack(count: Int, barWidth: CGFloat, height: CGFloat, gap: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<count, id: \.self) { index in
                let value = level(bands, index)
                RoundedRectangle(cornerRadius: barWidth * 0.45, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.spectrumTop.opacity(0.34), theme.spectrumBottom.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: max(1, height * value))
            }
        }
        .frame(height: height, alignment: .top)
    }

    // MARK: 取值

    private func level(_ values: [Float], _ index: Int) -> CGFloat {
        guard index < values.count else { return 0 }
        return CGFloat(min(1, max(0, values[index])))
    }
}
