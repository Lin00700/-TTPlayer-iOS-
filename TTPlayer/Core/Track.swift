import Foundation

// MARK: - 播放模式

enum RepeatMode: String, Codable, CaseIterable, Identifiable {
    case sequential
    case single
    case list
    case shuffle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .single: return "单曲循环"
        case .list: return "列表循环"
        case .shuffle: return "随机播放"
        }
    }

    var shortTitle: String {
        switch self {
        case .sequential: return "顺序"
        case .single: return "单曲"
        case .list: return "列表"
        case .shuffle: return "随机"
        }
    }

    var symbol: String {
        switch self {
        case .sequential: return "arrow.right"
        case .single: return "repeat.1"
        case .list: return "repeat"
        case .shuffle: return "shuffle"
        }
    }

    var next: RepeatMode {
        switch self {
        case .sequential: return .single
        case .single: return .list
        case .list: return .shuffle
        case .shuffle: return .sequential
        }
    }
}

// MARK: - 曲目

struct Track: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fileName: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var sampleRate: Double
    var bitrate: Double
    var channels: Int = 2
    var fileSize: Int64 = 0
    var addedAt: Date = Date()
    var badge: String = "AUDIO"
    var artworkFileName: String?

    var displayTitle: String {
        title.isEmpty ? fileName : title
    }

    var displayArtist: String {
        artist.isEmpty ? "未知艺术家" : artist
    }

    var displayAlbum: String {
        album.isEmpty ? "未知专辑" : album
    }
}

// MARK: - 格式化

enum TTFormat {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        if minutes >= 60 {
            let hours = minutes / 60
            return String(format: "%d:%02d:%02d", hours, minutes % 60, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func remaining(_ elapsed: Double, _ duration: Double) -> String {
        let left = max(0, duration - elapsed)
        return "-" + time(left)
    }

    static func sampleRate(_ rate: Double) -> String {
        guard rate > 0 else { return "—" }
        let khz = rate / 1000.0
        if abs(khz.rounded() - khz) < 0.05 {
            return String(format: "%.0f kHz", khz)
        }
        return String(format: "%.1f kHz", khz)
    }

    static func bitrate(_ kbps: Double) -> String {
        guard kbps > 0 else { return "—" }
        return String(format: "%.0f kbps", kbps)
    }

    static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(bytes) / 1024.0
        return String(format: "%.0f KB", kb)
    }
}

// MARK: - 格式徽标

enum AudioFormat {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "caf", "m4b", "mp4"
    ]

    static let lyricsExtensions: Set<String> = ["lrc", "txt"]

    static func badge(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "MP3"
        case "flac": return "FLAC"
        case "m4a", "m4b": return "M4A"
        case "aac": return "AAC"
        case "wav": return "WAV"
        case "aif", "aiff": return "AIFF"
        case "caf": return "CAF"
        case "mp4": return "MP4"
        default: return ext.uppercased()
        }
    }

    static func isAudio(_ ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }
}
