import AVFoundation
import Foundation

// MARK: - 持久化结构

struct PlayerSettings: Codable {
    var skin: SkinStyle = .classic
    var volume: Double = 0.85
    var repeatMode: RepeatMode = .list
    var equalizer: EqualizerSettings = .default
    var lyricOffsets: [String: Double] = [:]
    var showLyricsPanel: Bool = true
    var showPlaylistPanel: Bool = true
}

struct LibrarySnapshot: Codable {
    var tracks: [Track] = []
    var settings: PlayerSettings = PlayerSettings()
}

// MARK: - 文件库

/// Documents/Music 是曲库本体（也在「文件」App 里可见），Documents/library.json 存播放列表与设置。
final class Library {
    static let shared = Library()

    let documents: URL
    let musicDirectory: URL
    let artworkDirectory: URL
    private let stateURL: URL
    private let fileManager = FileManager.default

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        documents = docs
        musicDirectory = docs.appendingPathComponent("Music", isDirectory: true)
        artworkDirectory = docs.appendingPathComponent("Artwork", isDirectory: true)
        stateURL = docs.appendingPathComponent("library.json")
        ensureDirectories()
    }

    private func ensureDirectories() {
        for directory in [musicDirectory, artworkDirectory] {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: 路径

    func url(for track: Track) -> URL {
        musicDirectory.appendingPathComponent(track.fileName)
    }

    func artworkURL(for track: Track) -> URL? {
        guard let name = track.artworkFileName, !name.isEmpty else { return nil }
        let url = artworkDirectory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// 同名 .lrc（也接受 .txt），优先小写
    func lrcURL(for track: Track) -> URL? {
        let base = (track.fileName as NSString).deletingPathExtension
        for ext in ["lrc", "LRC", "txt", "TXT"] {
            let candidate = musicDirectory.appendingPathComponent("\(base).\(ext)")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    func audioFileNames() -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: musicDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let names = contents
            .filter { AudioFormat.isAudio($0.pathExtension) }
            .map { $0.lastPathComponent }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: 封面

    func writeArtwork(_ data: Data, for trackID: UUID) -> String? {
        let name = "\(trackID.uuidString).jpg"
        let url = artworkDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func removeArtwork(named name: String?) {
        guard let name = name, !name.isEmpty else { return }
        let url = artworkDirectory.appendingPathComponent(name)
        try? fileManager.removeItem(at: url)
    }

    // MARK: 删除

    func deleteTrackFile(_ track: Track) {
        try? fileManager.removeItem(at: url(for: track))
        removeArtwork(named: track.artworkFileName)
        if let lrc = lrcURL(for: track) {
            try? fileManager.removeItem(at: lrc)
        }
    }

    // MARK: 状态

    func loadState() -> LibrarySnapshot {
        guard let data = try? Data(contentsOf: stateURL) else {
            return LibrarySnapshot()
        }
        let decoder = JSONDecoder()
        guard var snapshot = try? decoder.decode(LibrarySnapshot.self, from: data) else {
            return LibrarySnapshot()
        }
        snapshot.settings.equalizer.normalize()
        return snapshot
    }

    @discardableResult
    func saveState(_ snapshot: LibrarySnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: stateURL, options: .atomic)
            return true
        } catch {
            NSLog("TTPlayer: save state failed — \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - 元数据

enum MetadataLoader {
    struct Metadata {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double = 0
        var sampleRate: Double = 0
        var channels: Int = 2
        var artwork: Data?
        var lyrics: String?
    }

    static func load(url: URL) async -> Metadata {
        await Task.detached(priority: .utility) { () -> Metadata in
            read(url: url)
        }.value
    }

    static func embeddedLyrics(url: URL) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let asset = AVURLAsset(url: url)
            for item in asset.metadata {
                let identifier = (item.identifier?.rawValue ?? "").lowercased()
                guard identifier.contains("lyric") || identifier.contains("uslt") else { continue }
                if let value = item.stringValue, !value.isEmpty {
                    return value
                }
            }
            return nil
        }.value
    }

    private static func read(url: URL) -> Metadata {
        var result = Metadata()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        let seconds = asset.duration.seconds
        if seconds.isFinite, seconds > 0 {
            result.duration = seconds
        }

        for item in asset.commonMetadata {
            let key = item.commonKey?.rawValue ?? ""
            switch key {
            case "title":
                result.title = item.stringValue
            case "artist":
                result.artist = item.stringValue
            case "albumName":
                result.album = item.stringValue
            case "artwork":
                result.artwork = item.dataValue
            default:
                break
            }
        }

        for item in asset.metadata {
            let identifier = (item.identifier?.rawValue ?? "").lowercased()
            if identifier.contains("lyric") || identifier.contains("uslt"),
               let value = item.stringValue, !value.isEmpty {
                result.lyrics = value
            }
        }

        if let audioFile = try? AVAudioFile(forReading: url) {
            let format = audioFile.processingFormat
            result.sampleRate = format.sampleRate
            result.channels = Int(format.channelCount)
            if result.duration <= 0, format.sampleRate > 0 {
                result.duration = Double(audioFile.length) / format.sampleRate
            }
        }

        return result
    }
}

// MARK: - 导入

enum MediaImporter {
    struct Summary {
        var addedTracks: [Track] = []
        var lyricsCount: Int = 0
        var failed: Int = 0
    }

    /// 单个 URL（文件或文件夹）导入，返回新增曲目
    static func importItem(_ url: URL, into library: Library) async -> Summary {
        var summary = Summary()
        let files = expand(url)

        for file in files where AudioFormat.isAudio(file.pathExtension) {
            if let track = await copyAudio(file, into: library) {
                summary.addedTracks.append(track)
            } else {
                summary.failed += 1
            }
        }
        for file in files where AudioFormat.lyricsExtensions.contains(file.pathExtension.lowercased()) {
            if copyLyrics(file, into: library) {
                summary.lyricsCount += 1
            }
        }
        return summary
    }

    static func expand(_ url: URL) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            return [url]
        }

        var files: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let item as URL in enumerator {
                let values = try? item.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                files.append(item)
            }
        }
        return files
    }

    private static func copyAudio(_ source: URL, into library: Library) async -> Track? {
        let fileManager = FileManager.default
        let ext = source.pathExtension.lowercased()
        guard AudioFormat.isAudio(ext) else { return nil }
        let baseName = source.deletingPathExtension().lastPathComponent
        let destination = uniqueDestination(in: library.musicDirectory, baseName: baseName, extension: ext)
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            NSLog("TTPlayer: copy \(source.lastPathComponent) failed — \(error.localizedDescription)")
            return nil
        }
        return await makeTrack(for: destination, in: library)
    }

    private static func copyLyrics(_ source: URL, into library: Library) -> Bool {
        let fileManager = FileManager.default
        let baseName = source.deletingPathExtension().lastPathComponent
        let destination = library.musicDirectory.appendingPathComponent("\(baseName).lrc")
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    static func makeTrack(for url: URL, in library: Library) async -> Track {
        let metadata = await MetadataLoader.load(url: url)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        var track = Track(
            fileName: url.lastPathComponent,
            title: metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? metadata.title! : fallbackTitle,
            artist: metadata.artist ?? "",
            album: metadata.album ?? "",
            duration: metadata.duration,
            sampleRate: metadata.sampleRate,
            bitrate: 0,
            channels: metadata.channels,
            badge: AudioFormat.badge(forExtension: url.pathExtension)
        )

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            track.fileSize = size.int64Value
        }
        if track.duration > 0, track.fileSize > 0 {
            track.bitrate = Double(track.fileSize) * 8 / track.duration / 1000
        }
        if let artwork = metadata.artwork, let name = library.writeArtwork(artwork, for: track.id) {
            track.artworkFileName = name
        }
        return track
    }

    static func uniqueDestination(in directory: URL, baseName: String, extension ext: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) (\(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }
}

// MARK: - 文本读取（兼容 GBK 歌词）

enum TextFileReader {
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let gbEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let text = String(data: data, encoding: String.Encoding(rawValue: gbEncoding)) {
            return text
        }
        return String(data: data, encoding: .isoLatin1)
    }
}
