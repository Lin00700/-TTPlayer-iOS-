import SwiftUI

/// 论文本宽度估算（等宽显示，避免为中国字/ASCII 混合测量反复触发 layout）。
enum TextMetrics {
    static func estimatedWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        for scalar in text.unicodeScalars {
            width += scalar.value < 128 ? fontSize * 0.56 : fontSize * 1.0
        }
        return width + 2
    }
}

/// LCD 式的横向走马灯标题：超出宽度才滚动，停下时静止。
struct MarqueeText: View {
    let text: String
    var fontSize: CGFloat = 17
    var weight: Font.Weight = .semibold
    var color: Color
    var speed: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let textWidth = TextMetrics.estimatedWidth(text, fontSize: fontSize)
            let overflow = textWidth - width
            let scrolling = overflow > 4
            let cycle = Double(textWidth + 46)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !scrolling)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let progress = cycle > 0 ? CGFloat(elapsed.truncatingRemainder(dividingBy: cycle / Double(speed))) * speed : 0

                HStack(spacing: 46) {
                    label
                    if scrolling {
                        label
                    }
                }
                .offset(x: scrolling ? -progress : 0)
                .frame(width: width, alignment: .leading)
            }
            .clipped()
        }
        .frame(height: fontSize * 1.4)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: fontSize, weight: weight, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
