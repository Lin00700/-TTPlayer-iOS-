import UIKit

/// 没有内嵌封面时，用经典千千静听风格现画一张 512×512 的锁屏封面。
enum ArtworkFactory {
    static func image(for track: Track, skin: SkinStyle, size: CGFloat = 512) -> UIImage {
        let canvas = CGSize(width: size, height: size)
        let palette = Palette(skin: skin)
        let renderer = UIGraphicsImageRenderer(size: canvas)

        return renderer.image { context in
            let cg = context.cgContext
            let colors = [palette.backgroundTop.cgColor, palette.backgroundBottom.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size),
                    options: []
                )
            }

            // 背景光晕
            let center = CGPoint(x: size * 0.5, y: size * 0.42)
            for step in 1...7 {
                let radius = size * (0.16 + CGFloat(step) * 0.032)
                cg.setFillColor(palette.accent.withAlphaComponent(0.022).cgColor)
                cg.fillEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }

            // 细边框
            let inset = size * 0.05
            cg.setStrokeColor(palette.border.cgColor)
            cg.setLineWidth(size * 0.0035)
            cg.stroke(CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))

            // 音符
            let noteRect = CGRect(x: 0, y: size * 0.22, width: size, height: size * 0.30)
            draw("♪", in: noteRect, font: UIFont.systemFont(ofSize: size * 0.30, weight: .light), color: palette.accent)

            // 分隔线
            let lineWidth = size * 0.18
            cg.setStrokeColor(palette.accent.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(size * 0.004)
            cg.move(to: CGPoint(x: size * 0.5 - lineWidth / 2, y: size * 0.575))
            cg.addLine(to: CGPoint(x: size * 0.5 + lineWidth / 2, y: size * 0.575))
            cg.strokePath()

            // 标题 / 艺术家
            draw(
                track.displayTitle,
                in: CGRect(x: size * 0.10, y: size * 0.60, width: size * 0.80, height: size * 0.16),
                font: UIFont.systemFont(ofSize: size * 0.072, weight: .semibold),
                color: palette.text
            )
            draw(
                track.displayArtist,
                in: CGRect(x: size * 0.10, y: size * 0.765, width: size * 0.80, height: size * 0.07),
                font: UIFont.systemFont(ofSize: size * 0.040, weight: .regular),
                color: palette.subtext
            )

            // 底部铭牌
            draw(
                "千千静听 · TTPlayer",
                in: CGRect(x: 0, y: size * 0.885, width: size, height: size * 0.05),
                font: UIFont.systemFont(ofSize: size * 0.030, weight: .medium),
                color: palette.accent.withAlphaComponent(0.85)
            )
        }
    }

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes,
            context: nil
        )
    }

    private struct Palette {
        let backgroundTop: UIColor
        let backgroundBottom: UIColor
        let accent: UIColor
        let text: UIColor
        let subtext: UIColor
        let border: UIColor

        init(skin: SkinStyle) {
            switch skin {
            case .classic:
                backgroundTop = UIColor(ttHex: 0x12202F)
                backgroundBottom = UIColor(ttHex: 0x050A11)
                accent = UIColor(ttHex: 0x7CC0F2)
                text = UIColor(ttHex: 0xEAF3FB)
                subtext = UIColor(ttHex: 0x9BB4C8)
                border = UIColor(ttHex: 0x2C7BC4, alpha: 0.55)
            case .ink:
                backgroundTop = UIColor(ttHex: 0x241F16)
                backgroundBottom = UIColor(ttHex: 0x0A0806)
                accent = UIColor(ttHex: 0xC9A86A)
                text = UIColor(ttHex: 0xEFE5D0)
                subtext = UIColor(ttHex: 0xA79B84)
                border = UIColor(ttHex: 0xA8362F, alpha: 0.6)
            }
        }
    }
}

extension UIColor {
    convenience init(ttHex hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
