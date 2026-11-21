import SwiftUI

// MARK: - 窗口外框

/// 经典千千静听的三段式窗口：一条金属标题栏 + 内嵌内容。
struct TTWindow<Content: View>: View {
    let theme: Theme
    let title: String
    var subtitle: String?
    var collapsed: Binding<Bool>?
    var trailing: AnyView?
    private let content: Content

    init(
        theme: Theme,
        title: String,
        subtitle: String? = nil,
        collapsed: Binding<Bool>? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.collapsed = collapsed
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if collapsed?.wrappedValue != true {
                content
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.windowGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.windowBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: theme.shadow, radius: 12, x: 0, y: 6)
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.accent)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.barText)
            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(theme.barTextDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let trailing = trailing {
                trailing
            }
            if let collapsed = collapsed {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        collapsed.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: collapsed.wrappedValue ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(theme.barTextDim)
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 27)
        .frame(maxWidth: .infinity)
        .background(
            theme.barGradient
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            Rectangle()
                .fill(theme.barBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - 小按钮

struct TTIconButton: View {
    let systemName: String
    let theme: Theme
    var active: Bool = false
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(active ? theme.accent : theme.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.windowGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.windowBorder.opacity(0.55), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }
}

struct TTSmallButton: View {
    let title: String
    let theme: Theme
    var filled: Bool = false
    var onBar: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(filled ? theme.pageBottom : (onBar ? theme.barText : theme.textPrimary))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(filled ? theme.accentSoft.opacity(0.9) : theme.windowBottom.opacity(onBar ? 0.35 : 0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.windowBorder.opacity(0.5), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
    }
}

struct TransportButton: View {
    let theme: Theme
    let symbol: String
    let size: CGFloat
    var primary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(primary ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.thumbGradient))
                Circle()
                    .strokeBorder(theme.windowBorder.opacity(0.65), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundColor(primary ? theme.pageBottom : theme.textPrimary)
                    .offset(x: symbol == "play.fill" ? size * 0.02 : 0)
            }
            .frame(width: size, height: size)
            .shadow(color: theme.shadow, radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 皮肤开关

struct SkinToggle: View {
    let theme: Theme
    let skin: SkinStyle
    let action: (SkinStyle) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SkinStyle.allCases) { style in
                Button {
                    action(style)
                } label: {
                    Text(style.shortTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(skin == style ? theme.pageBottom : theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 21)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(skin == style ? theme.accentSoft.opacity(0.9) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.windowBottom.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.windowBorder.opacity(0.5), lineWidth: 0.7)
        )
    }
}

// MARK: - 竖推子

struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let theme: Theme

    var body: some View {
        GeometryReader { geo in
            let height = max(1, geo.size.height)
            let span = range.upperBound - range.lowerBound
            let ratio = span > 0 ? (value - range.lowerBound) / span : 0
            let clamped = min(1, max(0, ratio))
            let filled = max(2, height * CGFloat(clamped))

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(theme.sliderTrack.opacity(0.55))
                    .frame(width: 5, height: height)
                Capsule()
                    .fill(theme.accentGradient)
                    .frame(width: 5, height: filled)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(theme.thumbGradient)
                    .frame(width: 17, height: 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5)
                            .strokeBorder(theme.windowBorder.opacity(0.7), lineWidth: 0.6)
                    )
                    .offset(y: -(height - 11) * CGFloat(clamped))
            }
            .frame(width: geo.size.width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let y = min(max(0, gesture.location.y), height)
                        let newRatio = 1 - Double(y / height)
                        let newValue = range.lowerBound + newRatio * span
                        value = min(range.upperBound, max(range.lowerBound, newValue))
                    }
            )
        }
    }
}

// MARK: - 提示条

struct ToastView: View {
    let theme: Theme
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(theme.accentSoft)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.isClassic ? Color.white.opacity(0.94) : theme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color.black.opacity(theme.isClassic ? 0.78 : 0.86))
        )
        .overlay(
            Capsule()
                .strokeBorder(theme.accent.opacity(0.45), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 播放中指示

struct PlayingIndicator: View {
    let theme: Theme
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: !active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = sin(time * 5.5 + Double(index) * 1.8)
                    let height = active ? 4 + (wave + 1) * 3.4 : 3.0
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 2, height: CGFloat(height))
                }
            }
            .frame(width: 16, height: 14, alignment: .bottom)
        }
    }
}
