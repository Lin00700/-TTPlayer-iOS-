import Foundation

// MARK: - 歌词行

struct LyricLine: Identifiable, Equatable {
    let id: Int
    /// 秒；-1 表示无时间轴的纯文本歌词
    let time: Double
    let text: String

    var isTimed: Bool { time >= 0 }
}

struct ParsedLyrics {
    var lines: [LyricLine] = []
    var title: String?
    var artist: String?
    var album: String?
    var offset: Double = 0

    var isEmpty: Bool { lines.isEmpty }

    var isTimed: Bool {
        lines.contains { $0.isTimed }
    }
}

// MARK: - LRC 解析

enum LRCParser {
    static func parse(_ raw: String) -> ParsedLyrics {
        var result = ParsedLyrics()
        var timed: [(Double, String)] = []
        var untimed: [String] = []
        var declaredOffset: Double = 0

        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for rawLine in normalized.components(separatedBy: "\n") {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            guard !rest.isEmpty else { continue }

            var times: [Double] = []
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let inside = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = rest[rest.index(after: close)...]

                if let seconds = timestamp(inside) {
                    times.append(seconds)
                } else {
                    let pieces = inside.split(separator: ":", maxSplits: 1).map(String.init)
                    if pieces.count == 2 {
                        let key = pieces[0].trimmingCharacters(in: .whitespaces).lowercased()
                        let value = pieces[1].trimmingCharacters(in: .whitespaces)
                        switch key {
                        case "ti": result.title = value
                        case "ar": result.artist = value
                        case "al": result.album = value
                        case "offset":
                            if let milliseconds = Int(value) {
                                declaredOffset = Double(milliseconds) / 1000.0
                            }
                        default: break
                        }
                    }
                }
            }

            let text = String(rest).trimmingCharacters(in: .whitespaces)
            if times.isEmpty {
                if !text.isEmpty {
                    untimed.append(text)
                }
            } else {
                for time in times {
                    timed.append((max(0, time), text))
                }
            }
        }

        result.offset = declaredOffset

        if !timed.isEmpty {
            timed.sort { $0.0 < $1.0 }
            var lines: [LyricLine] = []
            for (index, item) in timed.enumerated() {
                lines.append(LyricLine(id: index, time: item.0, text: item.1))
            }
            result.lines = lines
        } else {
            result.lines = untimed.enumerated().map { pair in
                LyricLine(id: pair.offset, time: -1, text: pair.element)
            }
        }

        return result
    }

    /// [mm:ss]、[mm:ss.xx]、[mm:ss,xxx] → 秒
    private static func timestamp(_ inside: String) -> Double? {
        let pieces = inside.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 2 else { return nil }
        let minuteText = pieces[0].trimmingCharacters(in: .whitespaces)
        guard let minutes = Int(minuteText), minutes >= 0 else { return nil }
        let secondText = pieces[1]
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let seconds = Double(secondText), seconds >= 0 else { return nil }
        return Double(minutes) * 60 + seconds
    }
}

// MARK: - 时间轴定位

enum LyricsTimeline {
    /// 返回当前应高亮的行索引（纯文本歌词返回 nil）
    static func activeIndex(lines: [LyricLine], elapsed: Double, offset: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        let target = elapsed + offset
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= target {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        if let index = found, lines[index].isTimed {
            return index
        }
        return nil
    }
}
