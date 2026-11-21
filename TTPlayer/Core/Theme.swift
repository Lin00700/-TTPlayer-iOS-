import SwiftUI

// MARK: - 皮肤

enum SkinStyle: String, Codable, CaseIterable, Identifiable {
    case classic
    case ink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "经典银灰"
        case .ink: return "水墨暗色"
        }
    }

    var shortTitle: String {
        switch self {
        case .classic: return "银灰"
        case .ink: return "水墨"
        }
    }

    var next: SkinStyle {
        self == .classic ? .ink : .classic
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - 主题

/// 两套皮肤共用的取色板。所有视图只从这里取色，切换皮肤时整套界面一起变。
struct Theme {
    let style: SkinStyle

    let pageTop: Color
    let pageBottom: Color
    let pageGlow: Color

    let windowTop: Color
    let windowBottom: Color
    let windowBorder: Color
    let windowInnerHighlight: Color

    let barTop: Color
    let barBottom: Color
    let barBorder: Color
    let barText: Color
    let barTextDim: Color

    let lcdTop: Color
    let lcdBottom: Color
    let lcdBorder: Color
    let lcdText: Color
    let lcdDim: Color
    let lcdGlow: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    let accent: Color
    let accentSoft: Color
    let accentDeep: Color

    let spectrumTop: Color
    let spectrumBottom: Color
    let spectrumPeak: Color

    let sliderTrack: Color
    let thumbTop: Color
    let thumbBottom: Color

    let rowBackground: Color
    let rowActive: Color
    let rowSeparator: Color

    let shadow: Color

    var isClassic: Bool { style == .classic }

    var pageBackground: LinearGradient {
        LinearGradient(colors: [pageTop, pageBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var windowGradient: LinearGradient {
        LinearGradient(colors: [windowTop, windowBottom], startPoint: .top, endPoint: .bottom)
    }

    var barGradient: LinearGradient {
        LinearGradient(colors: [barTop, barBottom], startPoint: .top, endPoint: .bottom)
    }

    var lcdGradient: LinearGradient {
        LinearGradient(colors: [lcdTop, lcdBottom], startPoint: .top, endPoint: .bottom)
    }

    var accentGradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent], startPoint: .top, endPoint: .bottom)
    }

    var spectrumGradient: LinearGradient {
        LinearGradient(colors: [spectrumTop, spectrumBottom], startPoint: .top, endPoint: .bottom)
    }

    var thumbGradient: LinearGradient {
        LinearGradient(colors: [thumbTop, thumbBottom], startPoint: .top, endPoint: .bottom)
    }

    var lcdFont: Font {
        .system(size: 13, weight: .medium, design: .monospaced)
    }

    var labelFont: Font {
        .system(size: 11, weight: .medium)
    }

    // MARK: 经典银灰金属

    static let classic = Theme(
        style: .classic,
        pageTop: Color(hex: 0x3B414D),
        pageBottom: Color(hex: 0x171A20),
        pageGlow: Color(hex: 0x5D6A80, opacity: 0.35),
        windowTop: Color(hex: 0xEDEFF4),
        windowBottom: Color(hex: 0xB3B9C4),
        windowBorder: Color(hex: 0x5C6472),
        windowInnerHighlight: Color.white.opacity(0.85),
        barTop: Color(hex: 0x8F99AB),
        barBottom: Color(hex: 0x545E70),
        barBorder: Color(hex: 0x2E3542),
        barText: Color(hex: 0xF2F5FA),
        barTextDim: Color(hex: 0xC5CDDA),
        lcdTop: Color(hex: 0x05121D),
        lcdBottom: Color(hex: 0x0A2237),
        lcdBorder: Color(hex: 0x060B12),
        lcdText: Color(hex: 0xA8ECFF),
        lcdDim: Color(hex: 0x4C8AA8),
        lcdGlow: Color(hex: 0x35C4F0),
        textPrimary: Color(hex: 0x22262E),
        textSecondary: Color(hex: 0x4C5464),
        textTertiary: Color(hex: 0x7B8494),
        accent: Color(hex: 0x2C7BC4),
        accentSoft: Color(hex: 0x7CC0F2),
        accentDeep: Color(hex: 0x17456F),
        spectrumTop: Color(hex: 0x2BD1F0),
        spectrumBottom: Color(hex: 0x1B62C6),
        spectrumPeak: Color(hex: 0xE4F8FF),
        sliderTrack: Color(hex: 0x8E97A6),
        thumbTop: Color(hex: 0xFDFEFF),
        thumbBottom: Color(hex: 0x9FA9B9),
        rowBackground: Color.white.opacity(0.42),
        rowActive: Color(hex: 0x2C7BC4, opacity: 0.20),
        rowSeparator: Color(hex: 0x8A92A1, opacity: 0.45),
        shadow: Color.black.opacity(0.35)
    )

    // MARK: 水墨暗色

    static let ink = Theme(
        style: .ink,
        pageTop: Color(hex: 0x1A1712),
        pageBottom: Color(hex: 0x07060A),
        pageGlow: Color(hex: 0x51422C, opacity: 0.35),
        windowTop: Color(hex: 0x272319),
        windowBottom: Color(hex: 0x15120D),
        windowBorder: Color(hex: 0x4A3F2C),
        windowInnerHighlight: Color(hex: 0xE9DCC0, opacity: 0.12),
        barTop: Color(hex: 0x352F23),
        barBottom: Color(hex: 0x1B1712),
        barBorder: Color(hex: 0x6B5B3D),
        barText: Color(hex: 0xEADFC6),
        barTextDim: Color(hex: 0xA79B84),
        lcdTop: Color(hex: 0x080706),
        lcdBottom: Color(hex: 0x14110B),
        lcdBorder: Color(hex: 0x2E271C),
        lcdText: Color(hex: 0xEFDCB2),
        lcdDim: Color(hex: 0x8B7A5A),
        lcdGlow: Color(hex: 0xC9A86A),
        textPrimary: Color(hex: 0xEDE4D0),
        textSecondary: Color(hex: 0xABA08A),
        textTertiary: Color(hex: 0x7E7461),
        accent: Color(hex: 0xA8362F),
        accentSoft: Color(hex: 0xD96A5C),
        accentDeep: Color(hex: 0x5E1C18),
        spectrumTop: Color(hex: 0xE0C083),
        spectrumBottom: Color(hex: 0xA8362F),
        spectrumPeak: Color(hex: 0xF8EDD3),
        sliderTrack: Color(hex: 0x3B342A),
        thumbTop: Color(hex: 0xD8BE8B),
        thumbBottom: Color(hex: 0x8A6E3F),
        rowBackground: Color.white.opacity(0.035),
        rowActive: Color(hex: 0xA8362F, opacity: 0.30),
        rowSeparator: Color(hex: 0x6A6152, opacity: 0.45),
        shadow: Color.black.opacity(0.6)
    )

    static func of(_ style: SkinStyle) -> Theme {
        style == .classic ? .classic : .ink
    }
}
