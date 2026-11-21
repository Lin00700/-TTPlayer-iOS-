import Foundation

// MARK: - 均衡器

struct EQPreset: Identifiable, Equatable {
    let name: String
    let gains: [Float]
    let preamp: Float

    var id: String { name }
}

struct EqualizerSettings: Codable, Equatable {
    /// 经典十段：31Hz / 62Hz / 125Hz / 250Hz / 500Hz / 1kHz / 2kHz / 4kHz / 8kHz / 16kHz
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let frequencyLabels: [String] = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var enabled: Bool = false
    var preamp: Float = 0
    var gains: [Float] = Array(repeating: 0, count: 10)
    var presetName: String = "默认"

    static let `default` = EqualizerSettings()

    static let presets: [EQPreset] = [
        EQPreset(name: "默认", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0),
        EQPreset(name: "流行", gains: [-1, 0, 1, 3, 4, 3, 1, 0, -1, -2], preamp: 0),
        EQPreset(name: "摇滚", gains: [5, 4, 2, -1, -2, 0, 3, 5, 6, 5], preamp: -2),
        EQPreset(name: "古典", gains: [3, 2, 1, 0, 0, 0, -1, -1, 2, 3], preamp: 0),
        EQPreset(name: "重低音", gains: [9, 8, 6, 3, 0, -1, -2, -3, -4, -4], preamp: -3),
        EQPreset(name: "人声", gains: [-3, -2, -1, 0, 3, 5, 5, 3, 1, -1], preamp: 0),
        EQPreset(name: "电子", gains: [4, 3, 1, 0, -1, 2, 4, 5, 4, 3], preamp: -1)
    ]

    mutating func apply(preset: EQPreset) {
        gains = preset.gains
        preamp = preset.preamp
        presetName = preset.name
    }

    mutating func reset() {
        gains = Array(repeating: 0, count: 10)
        preamp = 0
        presetName = "默认"
    }

    /// 把只可能来自 JSON 的数组补齐到 10 段，避免旧数据让界面越界
    mutating func normalize() {
        if gains.count != Self.frequencies.count {
            var fixed = Array(repeating: Float(0), count: Self.frequencies.count)
            for index in 0..<min(gains.count, fixed.count) {
                fixed[index] = gains[index]
            }
            gains = fixed
        }
        preamp = min(12, max(-12, preamp))
    }
}
