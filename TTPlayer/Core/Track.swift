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

    /// 已知的加密缓存格式：能认出来，但不解密，导入时直接说清原因
    static func encryptedKind(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "ncm":
            return "网易云 .ncm 加密缓存"
        case "qmc", "qmc0", "qmc3", "qmcflac", "qmcogg", "mflac", "mgg":
            return "QQ 音乐加密文件"
        case "kgm", "kgma":
            return "酷狗 .kgm 加密文件"
        case "kwm":
            return "酷我 .kwm 加密文件"
        case "xm":
            return "虾米加密文件"
        default:
            break
        }

        guard let head = header(url: url, length: 16) else { return nil }
        if head.starts(with: Array("CTENFDAM".utf8)) { return "网易云 .ncm 加密缓存" }
        if head.starts(with: Array("QTag".utf8)) { return "QQ 音乐加密文件" }
        if head.starts(with: [0x4B, 0x47, 0x4D]) { return "酷狗 .kgm 加密文件" }
        return nil
    }

    /// 按文件头猜真实格式。下载来的文件常常没有扩展名，或者后缀和内容不符（AAC 叫 .mp3），
    /// 认出来之后才能用正确的后缀落盘，AVAudioFile 也才愿意打开
    static func sniffExtension(url: URL) -> String? {
        guard let head = header(url: url, length: 16), head.count >= 12 else { return nil }

        func matches(_ text: String, at offset: Int = 0) -> Bool {
            let bytes = Array(text.utf8)
            guard head.count >= offset + bytes.count else { return false }
            return Array(head[offset..<(offset + bytes.count)]) == bytes
        }

        if matches("fLaC") { return "flac" }
        if matches("RIFF"), matches("WAVE", at: 8) { return "wav" }
        if matches("FORM"), matches("AIFF", at: 8) || matches("AIFC", at: 8) { return "aiff" }
        if matches("caff") { return "caf" }
        if matches("ID3") { return "mp3" }
        if matches("OggS") { return nil }
        if matches("MAC ") { return nil }
        if matches("ftyp", at: 4) { return "m4a" }

        // MPEG 音频帧同步：0xFFF1 / 0xFFF9 是 ADTS AAC，0xFFFB / 0xFFF3 是 MP3
        if head.count >= 2, head[0] == 0xFF, (head[1] & 0xE0) == 0xE0 {
            if (head[1] & 0xF6) == 0xF0 { return "aac" }
            return "mp3"
        }

        return nil
    }

    private static func header(url: URL, length: Int) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: length), !data.isEmpty else { return nil }
        return [UInt8](data)
    }
}
