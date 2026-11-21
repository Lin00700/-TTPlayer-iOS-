import SwiftUI
import UIKit

// MARK: - 视觉播放模式

enum VisualMode: String, Codable, CaseIterable, Identifiable {
    case spectrum
    case oscilloscope
    case vinyl
    case nebula

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrum: return "经典频谱"
        case .oscilloscope: return "声波示波器"
        case .vinyl: return "黑胶脉冲"
        case .nebula: return "律动星环"
        }
    }

    var shortTitle: String {
        switch self {
        case .spectrum: return "频谱"
        case .oscilloscope: return "示波"
        case .vinyl: return "黑胶"
        case .nebula: return "星环"
        }
    }

    var symbol: String {
        switch self {
        case .spectrum: return "chart.bar.fill"
        case .oscilloscope: return "waveform.path.ecg"
        case .vinyl: return "record.circle"
        case .nebula: return "circle.hexagongrid.fill"
        }
    }

    var hint: String {
        switch self {
        case .spectrum: return "24 段辉光柱体 · 镜面倒影"
        case .oscilloscope: return "多层声波曲线 · 随低频起伏"
        case .vinyl: return "旋转黑胶 · 36 道光芒脉冲"
        case .nebula: return "漂浮粒子 · 同心能量环"
        }
    }

    var next: VisualMode {
        let all = VisualMode.allCases
        guard let index = all.firstIndex(of: self) else { return .spectrum }
        return all[(index + 1) % all.count]
    }
}

// MARK: - 能量分组

/// 把 24 段频谱压成低 / 中 / 高三组能量，供示波器、黑胶和星环使用。
struct SpectrumEnergy {
    let low: Double
    let mid: Double
    let high: Double
    let level: Double
    /// 低频冲击量，0…1，用来驱动脉冲环
    let punch: Double

    init(bands: [Float]) {
        let values = bands.map { Double(min(1, max(0, $0))) }
        guard !values.isEmpty else {
            low = 0
            mid = 0
            high = 0
            level = 0
            punch = 0
            return
        }

        let count = values.count
        let first = max(1, count / 3)
        let second = max(first + 1, (count * 2) / 3)
        low = SpectrumEnergy.average(values[0..<min(first, count)])
        mid = SpectrumEnergy.average(values[min(first, count)..<min(second, count)])
        high = SpectrumEnergy.average(values[min(second, count)..<count])
        level = SpectrumEnergy.average(values[...])
        punch = min(1, max(0, (low - 0.32) / 0.68))
    }

    static func average(_ slice: ArraySlice<Double>) -> Double {
        guard !slice.isEmpty else { return 0 }
        return slice.reduce(0, +) / Double(slice.count)
    }

    /// 按 0…1 的横向位置在 24 段之间线性取样
    static func bandValue(_ bands: [Float], at position: Double) -> Double {
        guard !bands.isEmpty else { return 0 }
        if bands.count == 1 { return Double(min(1, max(0, bands[0]))) }
        let clamped = min(1, max(0, position))
        let location = clamped * Double(bands.count - 1)
        let index = Int(location)
        let fraction = location - Double(index)
        let first = Double(min(1, max(0, bands[index])))
        let second = Double(min(1, max(0, bands[min(bands.count - 1, index + 1)])))
        return first + (second - first) * fraction
    }
}

// MARK: - 视觉播放主体

/// 四种视觉播放共用一个入口：主窗口里的小窗和全屏舞台都挂这个视图。
struct VisualizerView: View {
    let mode: VisualMode
    let bands: [Float]
    let peaks: [Float]
    let theme: Theme
    let elapsed: Double
    let isPlaying: Bool
    var artwork: UIImage?
    var large: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: large ? 1.0 / 30.0 : 1.0 / 22.0, paused: !isPlaying)) { timeline in
            content(time: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    @ViewBuilder
    private func content(time: Double) -> some View {
        switch mode {
        case .spectrum:
            SpectrumView(bands: bands, peaks: peaks, theme: theme)
        case .oscilloscope:
            OscilloscopeVisual(bands: bands, theme: theme, time: time, active: isPlaying)
        case .vinyl:
            VinylVisual(bands: bands, theme: theme, elapsed: elapsed, active: isPlaying, artwork: artwork)
        case .nebula:
            NebulaVisual(bands: bands, theme: theme, time: time, active: isPlaying)
        }
    }
}

// MARK: - 声波示波器

/// 三层发光的声波曲线：横向位置对应频段、振幅随低频能量起伏，错相位滚动。
struct OscilloscopeVisual: View {
    let bands: [Float]
    let theme: Theme
    let time: Double
    let active: Bool

    private struct Layer {
        let cycles: Double
        let speed: Double
        let lineWidth: CGFloat
        let opacity: Double
        let gain: CGFloat
    }

    private let layers: [Layer] = [
        Layer(cycles: 2.4, speed: 0.55, lineWidth: 1.7, opacity: 0.95, gain: 1.0),
        Layer(cycles: 4.3, speed: -0.82, lineWidth: 1.15, opacity: 0.55, gain: 0.78),
        Layer(cycles: 6.9, speed: 1.15, lineWidth: 0.8, opacity: 0.32, gain: 0.58)
    ]

    var body: some View {
        let energy = SpectrumEnergy(bands: bands)
        Canvas { context, size in
            let midY = size.height / 2
            drawGrid(&context, size: size, midY: midY)

            let amplitude = size.height * 0.40 * CGFloat(0.22 + 0.78 * energy.level) * (active ? 1 : 0.6)

            for layer in layers {
                let path = wavePath(
                    size: size,
                    midY: midY,
                    phase: time * layer.speed,
                    layer: layer,
                    amplitude: amplitude,
                    low: energy.low
                )

                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 5))
                    glow.stroke(
                        path,
                        with: .color(theme.spectrumTop.opacity(layer.opacity * 0.55)),
                        lineWidth: layer.lineWidth * 2.2
                    )
                }

                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            theme.accentSoft.opacity(layer.opacity),
                            theme.spectrumPeak.opacity(layer.opacity),
                            theme.spectrumTop.opacity(layer.opacity),
                            theme.accent.opacity(layer.opacity)
                        ]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ),
                    lineWidth: layer.lineWidth
                )
            }
        }
    }

    private func wavePath(
        size: CGSize,
        midY: CGFloat,
        phase: Double,
        layer: Layer,
        amplitude: CGFloat,
        low: Double
    ) -> Path {
        var path = Path()
        let steps = max(28, Int(size.width / 3))
        let bass = 0.55 + 0.45 * low

        for index in 0...steps {
            let t = Double(index) / Double(steps)
            let band = SpectrumEnergy.bandValue(bands, at: t)
            let envelope = 0.16 + 0.84 * band
            let angle = t * layer.cycles * 2 * Double.pi + phase * 2 * Double.pi
            let wobble = sin(angle) * 0.74 + sin(angle * 2.17 + phase * 1.7) * 0.26
            let offset = CGFloat(wobble * envelope * bass) * amplitude * layer.gain
            let point = CGPoint(x: CGFloat(t) * size.width, y: midY - offset)

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func drawGrid(_ context: inout GraphicsContext, size: CGSize, midY: CGFloat) {
        var grid = Path()
        for column in 1..<8 {
            let x = size.width * CGFloat(column) / 8
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for row in 1..<4 {
            let y = size.height * CGFloat(row) / 4
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(theme.accent.opacity(0.10)), lineWidth: 0.5)

        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: midY))
        axis.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(axis, with: .color(theme.accent.opacity(0.22)), lineWidth: 0.6)
    }
}

// MARK: - 黑胶脉冲

/// 旋转的老式黑胶（有封面就贴封面，没有就画经典 TTPlayer 标签），
/// 外圈 36 道放射光芒跟着频段起伏，低频打下来时脉冲环向外扩。
struct VinylVisual: View {
    let bands: [Float]
    let theme: Theme
    let elapsed: Double
    let active: Bool
    var artwork: UIImage?

    private let rayCount = 36

    var body: some View {
        GeometryReader { geo in
            let energy = SpectrumEnergy(bands: bands)
            let side = min(geo.size.width, geo.size.height)
            let discSize = side * 0.70
            let discRadius = discSize / 2
            let ringRadius = side * 0.5
            let maxRay = max(2, ringRadius - discRadius - 6)

            ZStack {
                ForEach(0..<rayCount, id: \.self) { index in
                    ray(index: index, base: discRadius + 3, maxRay: maxRay, width: max(1.2, side * 0.011))
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(Double(index) * 360.0 / Double(rayCount)))
                }

                // 低频脉冲环
                Circle()
                    .strokeBorder(
                        theme.accentSoft.opacity(0.18 + 0.5 * energy.punch),
                        lineWidth: 1 + 1.6 * CGFloat(energy.punch)
                    )
                    .frame(width: discSize * (1.10 + 0.14 * CGFloat(energy.punch)))
                    .blur(radius: 1.2)

                Circle()
                    .strokeBorder(
                        theme.spectrumTop.opacity(0.10 + 0.28 * energy.mid),
                        lineWidth: 0.8
                    )
                    .frame(width: discSize * (1.30 + 0.10 * CGFloat(energy.mid)))

                disc(discSize: discSize)
                    .rotationEffect(.degrees(elapsed * 198))
                    .animation(.linear(duration: 0.14), value: elapsed)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: 光芒

    private func ray(index: Int, base: CGFloat, maxRay: CGFloat, width: CGFloat) -> some View {
        let value = rayValue(index)
        let length = max(2, maxRay * (0.22 + 0.78 * value))
        return Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [theme.spectrumTop.opacity(0.85), theme.spectrumBottom.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: length)
            .offset(y: -(base + length / 2))
            .shadow(color: theme.spectrumTop.opacity(0.35 * Double(value)), radius: 3)
    }

    private func rayValue(_ index: Int) -> CGFloat {
        guard !bands.isEmpty else { return 0 }
        let position = Double(index) / Double(rayCount)
        let mirrored = position <= 0.5 ? position * 2 : (1 - position) * 2
        return CGFloat(SpectrumEnergy.bandValue(bands, at: mirrored))
    }

    // MARK: 碟片

    private func disc(discSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x2A2A2E), Color(hex: 0x101013), Color(hex: 0x050507)],
                        center: .center,
                        startRadius: discSize * 0.05,
                        endRadius: discSize * 0.52
                    )
                )

            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .strokeBorder(
                        Color.white.opacity(index % 2 == 0 ? 0.055 : 0.028),
                        lineWidth: 0.6
                    )
                    .frame(
                        width: discSize * (0.48 + CGFloat(index) * 0.048),
                        height: discSize * (0.48 + CGFloat(index) * 0.048)
                    )
            }

            label(discSize: discSize)

            Circle()
                .fill(Color.black.opacity(0.9))
                .frame(width: max(2, discSize * 0.028), height: max(2, discSize * 0.028))
        }
        .frame(width: discSize, height: discSize)
        .overlay(
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.clear,
                            Color.clear,
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            Circle()
                .strokeBorder(theme.windowBorder.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: theme.shadow, radius: 10, x: 0, y: 5)
    }

    @ViewBuilder
    private func label(discSize: CGFloat) -> some View {
        if let image = artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: discSize * 0.36, height: discSize * 0.36)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(theme.windowBorder.opacity(0.6), lineWidth: 0.8)
                )
        } else {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                VStack(spacing: 1) {
                    Text("千千静听")
                        .font(.system(size: max(6, discSize * 0.105), weight: .bold, design: .serif))
                        .foregroundColor(theme.lcdTop)
                        .lineLimit(1)
                    Text("TTPlayer")
                        .font(.system(size: max(4.5, discSize * 0.055), weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.lcdTop.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(2)
            }
            .frame(width: discSize * 0.36, height: discSize * 0.36)
            .overlay(
                Circle().strokeBorder(theme.windowBorder.opacity(0.6), lineWidth: 0.8)
            )
        }
    }
}

// MARK: - 律动星环

/// 漂浮粒子 + 三层同心能量环，低 / 中 / 高频各驱动一环，粒子跟着频段闪。
struct NebulaVisual: View {
    let bands: [Float]
    let theme: Theme
    let time: Double
    let active: Bool

    private let particleCount = 56

    var body: some View {
        let energy = SpectrumEnergy(bands: bands)
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let unit = min(size.width, size.height)

            // 中心光晕
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: unit * 0.08))
                let radius = unit * (0.10 + 0.14 * CGFloat(energy.level))
                glow.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            theme.accentSoft.opacity(0.45),
                            theme.accent.opacity(0.12),
                            theme.accent.opacity(0)
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }

            // 同心能量环
            for ring in 0..<3 {
                let drive = ring == 0 ? energy.low : (ring == 1 ? energy.mid : energy.high)
                let radius = unit * (0.16 + CGFloat(ring) * 0.11) * (1 + 0.26 * CGFloat(drive))
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(theme.accent.opacity(0.12 + 0.40 * drive)),
                    lineWidth: 0.9 + CGFloat(drive) * 1.4
                )
            }

            // 漂浮粒子
            for index in 0..<particleCount {
                let band = SpectrumEnergy.bandValue(
                    bands,
                    at: NebulaVisual.random(index, 4)
                )
                let angle = NebulaVisual.random(index, 1) * 2 * Double.pi
                    + time * (0.16 + 0.42 * NebulaVisual.random(index, 3))
                    * (index % 2 == 0 ? 1 : -1)
                let spread = CGFloat(0.09 + 0.36 * NebulaVisual.random(index, 2))
                let orbit = unit * spread * CGFloat(1 + 0.22 * band)
                let x = center.x + CGFloat(cos(angle)) * orbit
                let y = center.y + CGFloat(sin(angle)) * orbit
                let sizeFactor = CGFloat(0.006 + 0.017 * band)
                    * CGFloat(1 + 0.5 * NebulaVisual.random(index, 5))
                    * (active ? 1 : 0.7)
                let dot = max(0.8, unit * sizeFactor)

                let color = band > 0.55 ? theme.spectrumPeak : theme.spectrumTop
                let rect = CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)

                if index % 4 == 0 {
                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius: max(1.5, dot * 1.6)))
                        glow.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.55)))
                    }
                }
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.35 + 0.6 * band)))
            }
        }
    }

    /// 稳定的伪随机（同一个 index 每帧位置一致），避免粒子乱跳
    static func random(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
        return value - floor(value)
    }
}
