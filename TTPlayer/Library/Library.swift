import AVFoundation
import CoreMedia
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

    func ensureDirectories() {
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
        } else if let track = asset.tracks(withMediaType: .audio).first {
            // AVAudioFile 打不开（非标准头 / 后缀和内容不符）时退回 AVAsset 的格式描述，
            // 采样率读数就不会只剩一个「—」
            if let description = track.formatDescriptions.first {
                let format = description as! CMFormatDescription
                if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    if basic.mSampleRate.isFinite, basic.mSampleRate > 0 {
                        result.sampleRate = basic.mSampleRate
                    }
                    if basic.mChannelsPerFrame > 0 {
                        result.channels = Int(basic.mChannelsPerFrame)
                    }
                }
            }
            if result.duration <= 0 {
                let range = track.timeRange.duration.seconds
                if range.isFinite, range > 0 {
                    result.duration = range
                }
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
        var failures: [String] = []

        mutating func recordFailure(_ message: String) {
            failed += 1
            if failures.count < 4 {
                failures.append(message)
            }
        }

        var isEmpty: Bool {
            addedTracks.isEmpty && lyricsCount == 0
        }
    }

    /// 单个 URL（文件或文件夹）导入：自己处理安全作用域，调用方不用再管
    static func importItem(_ url: URL, into library: Library) async -> Summary {
        var summary = Summary()
        library.ensureDirectories()

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)

        let files = expand(url)
        guard !files.isEmpty else {
            if !exists {
                summary.recordFailure("\(url.lastPathComponent)：读不到这个位置（iCloud 可能还没下载完）")
            } else if isDirectory.boolValue {
                summary.recordFailure("\(url.lastPathComponent)：文件夹里没有文件")
            }
            return summary
        }

        for file in files {
            let ext = file.pathExtension.lowercased()

            if AudioFormat.lyricsExtensions.contains(ext) {
                do {
                    try copyLyrics(file, into: library)
                    summary.lyricsCount += 1
                } catch {
                    summary.recordFailure("\(file.lastPathComponent)：\(friendly(error))")
                }
                continue
            }

            if let kind = AudioFormat.encryptedKind(for: file) {
                summary.recordFailure("\(file.lastPathComponent)：\(kind)，要先解密成普通音频")
                continue
            }

            var resolvedExtension = ext
            if !AudioFormat.isAudio(resolvedExtension) {
                resolvedExtension = AudioFormat.sniffExtension(url: file) ?? ""
            }

            guard AudioFormat.isAudio(resolvedExtension) else {
                // 文件夹里的图片、封面之类默默略过，单独选中的文件才报错
                if !isDirectory.boolValue {
                    summary.recordFailure("\(file.lastPathComponent)：不是可识别的音频文件")
                }
                continue
            }

            do {
                let track = try await copyAudio(file, extension: resolvedExtension, into: library)
                summary.addedTracks.append(track)
            } catch {
                summary.recordFailure("\(file.lastPathComponent)：\(friendly(error))")
            }
        }

        if summary.isEmpty, summary.failed == 0 {
            summary.recordFailure("\(url.lastPathComponent)：没找到可导入的歌曲或歌词")
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

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        func walk(_ root: URL) -> [URL] {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            var files: [URL] = []
            for case let item as URL in enumerator {
                let name = item.lastPathComponent
                if name == "__MACOSX" || name.hasPrefix("._") { continue }
                let values = try? item.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                files.append(item)
            }
            return files
        }

        // 文件夹在 iCloud Drive / 第三方文件 App 里时，先协调读取一次再枚举
        var coordinated: [URL] = []
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinatorError) { readURL in
            coordinated = walk(readURL)
        }
        if !coordinated.isEmpty {
            return coordinated
        }
        return walk(url)
    }

    private static func copyAudio(_ source: URL, extension ext: String, into library: Library) async throws -> Track {
        library.ensureDirectories()
        let baseName = source.deletingPathExtension().lastPathComponent
        let destination = uniqueDestination(in: library.musicDirectory, baseName: baseName, extension: ext)
        try coordinatedCopy(from: source, to: destination)
        return await makeTrack(for: destination, in: library)
    }

    private static func copyLyrics(_ source: URL, into library: Library) throws {
        library.ensureDirectories()
        let baseName = source.deletingPathExtension().lastPathComponent
        let destination = library.musicDirectory.appendingPathComponent("\(baseName).lrc")
        try coordinatedCopy(from: source, to: destination)
    }

    /// 读安全作用域 / 文件 App 里的文件统一走 NSFileCoordinator：
    /// iCloud 没下载的会在这里触发下载，第三方 App 的沙箱文件也才能读到
    private static func coordinatedCopy(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        var coordinatorError: NSError?
        var copyError: Error?

        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatorError) { readURL in
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: readURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let copyError = copyError {
            throw copyError
        }
        if let coordinatorError = coordinatorError {
            throw coordinatorError
        }
        guard fileManager.fileExists(atPath: destination.path) else {
            throw MediaImportError.copyFailed("复制没有成功")
        }
    }

    private static func friendly(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else {
            return nsError.localizedDescription
        }
        switch nsError.code {
        case CocoaError.Code.fileNoSuchFile.rawValue, CocoaError.Code.fileReadNoSuchFile.rawValue:
            return "文件读不到（iCloud 没下载完或已经被移走）"
        case CocoaError.Code.fileReadNoPermission.rawValue, CocoaError.Code.fileWriteNoPermission.rawValue:
            return "没有读取权限"
        case CocoaError.Code.fileWriteOutOfSpace.rawValue:
            return "手机空间不足"
        default:
            return nsError.localizedDescription
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

enum MediaImportError: LocalizedError {
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let reason):
            return reason
        }
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
