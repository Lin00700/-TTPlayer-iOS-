import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

/// 整个 App 的中枢：曲库、播放队列、歌词同步、皮肤与设置、锁屏控制。
final class PlayerStore: ObservableObject {
    let library = Library.shared
    let wifi = WifiUploadServer()

    private let engine = AudioEngineController()
    private var ticker: Timer?
    private var saveWorkItem: DispatchWorkItem?
    private var lyricsTask: Task<Void, Never>?
    private var artworkCache: [UUID: UIImage] = [:]
    private var lyricOffsets: [String: Double] = [:]

    // MARK: 曲库

    @Published private(set) var tracks: [Track] = []
    @Published var searchText: String = ""

    // MARK: 播放状态

    @Published private(set) var currentTrackID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var spectrum = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    @Published private(set) var spectrumPeaks = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)

    // MARK: 显示读数

    @Published private(set) var formatText: String = "—"
    @Published private(set) var rateText: String = "—"
    @Published private(set) var bitrateText: String = "—"

    // MARK: 设置

    @Published var volume: Double = 0.85 {
        didSet {
            engine.setVolume(Float(volume))
            scheduleSave()
        }
    }

    @Published var repeatMode: RepeatMode = .list {
        didSet { scheduleSave() }
    }

    @Published var skin: SkinStyle = .classic {
        didSet { scheduleSave() }
    }

    @Published var equalizer = EqualizerSettings.default {
        didSet {
            engine.apply(equalizer: equalizer)
            scheduleSave()
        }
    }

    @Published var showLyricsPanel = true {
        didSet { scheduleSave() }
    }

    @Published var showPlaylistPanel = true {
        didSet { scheduleSave() }
    }

    // MARK: 歌词

    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsSource: String = ""
    @Published private(set) var currentLyricIndex: Int?

    @Published var lyricOffset: Double = 0 {
        didSet {
            storeLyricOffset()
            scheduleSave()
        }
    }

    // MARK: 界面

    @Published var showEqualizer = false
    @Published var showWifi = false
    @Published var toast: String?
    @Published private(set) var isImporting = false
    @Published private(set) var importDone = 0
    @Published private(set) var importTotal = 0

    // MARK: - 生命周期

    init() {
        let snapshot = library.loadState()
        tracks = snapshot.tracks
        let settings = snapshot.settings

        volume = settings.volume
        repeatMode = settings.repeatMode
        skin = settings.skin
        var storedEQ = settings.equalizer
        storedEQ.normalize()
        equalizer = storedEQ
        lyricOffsets = settings.lyricOffsets
        showLyricsPanel = settings.showLyricsPanel
        showPlaylistPanel = settings.showPlaylistPanel

        engine.setVolume(Float(settings.volume))
        engine.apply(equalizer: storedEQ)

        engine.onFinished = { [weak self] in
            DispatchQueue.main.async {
                self?.handleTrackFinished()
            }
        }

        engine.onSpectrum = { [weak self] bands, peaks in
            DispatchQueue.main.async {
                self?.spectrum = bands
                self?.spectrumPeaks = peaks
            }
        }

        setupRemoteCommands()
        observeSessionNotifications()
        startTicker()
        refreshFromDisk()

        wifi.onLibraryChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshFromDisk()
            }
        }
    }

    deinit {
        ticker?.invalidate()
    }

    // MARK: - 计算属性

    var currentTrack: Track? {
        guard let id = currentTrackID else { return nil }
        return tracks.first { $0.id == id }
    }

    var currentIndex: Int? {
        guard let id = currentTrackID else { return nil }
        return tracks.firstIndex { $0.id == id }
    }

    var hasTrack: Bool { currentTrackID != nil }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    var theme: Theme { Theme.of(skin) }

    // MARK: - 播放

    func playTrack(_ track: Track) {
        guard let index = tracks.firstIndex(of: track) else {
            play(index: tracks.count)
            return
        }
        play(index: index)
    }

    func play(index: Int) {
        guard tracks.indices.contains(index) else { return }
        let track = tracks[index]

        do {
            let info = try engine.open(url: library.url(for: track))
            currentTrackID = track.id
            duration = info.duration > 0 ? info.duration : track.duration
            elapsed = 0
            formatText = track.badge
            rateText = TTFormat.sampleRate(info.sampleRate > 0 ? info.sampleRate : track.sampleRate)
            bitrateText = TTFormat.bitrate(track.bitrate)
            lyricOffset = lyricOffsets[track.id.uuidString] ?? 0
            engine.play(from: 0)
            isPlaying = true
            loadLyrics(for: track)
            updateNowPlaying()
        } catch {
            currentTrackID = track.id
            isPlaying = false
            duration = track.duration
            elapsed = 0
            lyrics = []
            currentLyricIndex = nil
            toast = "无法播放《\(track.displayTitle)》：\(error.localizedDescription)"
            updateNowPlaying()
        }
    }

    func togglePlayPause() {
        guard currentTrackID != nil else {
            if let first = tracks.first {
                playTrack(first)
            }
            return
        }
        if isPlaying {
            engine.pause()
            isPlaying = false
        } else {
            if !engine.isLoaded, let track = currentTrack {
                playTrack(track)
                return
            }
            if duration > 0, elapsed >= duration - 0.15 {
                engine.play(from: 0)
                elapsed = 0
            } else {
                engine.resume()
            }
            isPlaying = true
        }
        updateNowPlaying()
    }

    func next() {
        guard !tracks.isEmpty else { return }
        guard let index = currentIndex else {
            play(index: 0)
            return
        }
        if repeatMode == .shuffle {
            play(index: randomIndex(excluding: index))
            return
        }
        if index + 1 < tracks.count {
            play(index: index + 1)
        } else {
            play(index: 0)
        }
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        guard let index = currentIndex else {
            play(index: 0)
            return
        }
        if repeatMode == .shuffle {
            play(index: randomIndex(excluding: index))
            return
        }
        if index > 0 {
            play(index: index - 1)
        } else {
            play(index: tracks.count - 1)
        }
    }

    func seek(to seconds: Double) {
        guard currentTrackID != nil else { return }
        let clamped = max(0, min(seconds, max(duration, 0)))
        engine.seek(to: clamped)
        elapsed = clamped
        updateCurrentLyric()
        updateNowPlaying()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        toast = "播放模式：\(repeatMode.title)"
    }

    private func randomIndex(excluding index: Int?) -> Int {
        guard tracks.count > 1 else { return 0 }
        var candidate = Int.random(in: 0..<tracks.count)
        var guardCount = 0
        while candidate == index, guardCount < 12 {
            candidate = Int.random(in: 0..<tracks.count)
            guardCount += 1
        }
        return candidate
    }

    private func handleTrackFinished() {
        guard !tracks.isEmpty else {
            isPlaying = false
            return
        }
        switch repeatMode {
        case .single:
            engine.play(from: 0)
            elapsed = 0
            isPlaying = true
            updateNowPlaying()
        case .list:
            guard let index = currentIndex else {
                play(index: 0)
                return
            }
            play(index: (index + 1) % tracks.count)
        case .shuffle:
            play(index: randomIndex(excluding: currentIndex))
        case .sequential:
            guard let index = currentIndex else {
                play(index: 0)
                return
            }
            if index + 1 < tracks.count {
                play(index: index + 1)
            } else {
                isPlaying = false
                elapsed = duration
                updateNowPlaying()
            }
        }
    }

    // MARK: - 计时

    private func startTicker() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard currentTrackID != nil else { return }
        if isPlaying {
            elapsed = engine.currentTime
            updateCurrentLyric()
        } else {
            decaySpectrum()
        }
    }

    private func decaySpectrum() {
        guard spectrum.contains(where: { $0 > 0.002 }) else { return }
        var bands = spectrum
        var peaks = spectrumPeaks
        for index in bands.indices {
            bands[index] = bands[index] > 0.002 ? bands[index] * 0.88 : 0
            let target = max(bands[index], peaks[index] - 0.03)
            peaks[index] = target > 0.002 ? target : 0
        }
        spectrum = bands
        spectrumPeaks = peaks
    }

    // MARK: - 歌词

    func loadLyrics(for track: Track) {
        lyricsTask?.cancel()
        lyrics = []
        lyricsSource = ""
        currentLyricIndex = nil

        let sidecar = library.lrcURL(for: track)
        let fileURL = library.url(for: track)

        lyricsTask = Task { [weak self] in
            var text: String?
            var source = ""

            if let sidecar = sidecar, let content = TextFileReader.read(sidecar) {
                text = content
                source = "LRC 文件"
            }

            if text == nil, let embedded = await MetadataLoader.embeddedLyrics(url: fileURL) {
                text = embedded
                source = "内嵌歌词"
            }

            guard let raw = text else { return }
            let parsed = LRCParser.parse(raw)
            guard !parsed.lines.isEmpty else { return }

            await MainActor.run {
                guard let self = self else { return }
                guard self.currentTrackID == track.id else { return }
                self.lyrics = parsed.lines
                self.lyricsSource = source
                self.updateCurrentLyric()
            }
        }
    }

    func updateCurrentLyric() {
        guard !lyrics.isEmpty else {
            if currentLyricIndex != nil { currentLyricIndex = nil }
            return
        }
        let index = LyricsTimeline.activeIndex(lines: lyrics, elapsed: elapsed, offset: lyricOffset)
        if index != currentLyricIndex {
            currentLyricIndex = index
        }
    }

    func seekToLyric(_ line: LyricLine) {
        guard line.isTimed else { return }
        seek(to: max(0, line.time - lyricOffset))
    }

    func nudgeLyricOffset(_ delta: Double) {
        var value = lyricOffset + delta
        value = (value * 10).rounded() / 10
        value = min(10, max(-10, value))
        lyricOffset = value
        updateCurrentLyric()
    }

    func resetLyricOffset() {
        lyricOffset = 0
        updateCurrentLyric()
    }

    private func storeLyricOffset() {
        guard let id = currentTrackID else { return }
        lyricOffsets[id.uuidString] = lyricOffset
    }

    func importLyrics(from url: URL) {
        guard let track = currentTrack else {
            toast = "先播放一首歌，再导入它的歌词"
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let base = (track.fileName as NSString).deletingPathExtension
        let destination = library.musicDirectory.appendingPathComponent("\(base).lrc")
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            loadLyrics(for: track)
            toast = "已导入歌词：\(destination.lastPathComponent)"
        } catch {
            toast = "导入歌词失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 曲库操作

    func refreshFromDisk() {
        let names = library.audioFileNames()
        let known = Dictionary(tracks.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })

        var updated: [Track] = []
        var pending: [String] = []
        for name in names {
            if let existing = known[name] {
                updated.append(existing)
            } else {
                pending.append(name)
            }
        }

        if updated != tracks {
            tracks = updated
        }
        guard !pending.isEmpty else {
            scheduleSave()
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            var added: [Track] = []
            for name in pending {
                let url = self.library.musicDirectory.appendingPathComponent(name)
                let track = await MediaImporter.makeTrack(for: url, in: self.library)
                added.append(track)
            }
            await MainActor.run {
                for track in added where !self.tracks.contains(where: { $0.fileName == track.fileName }) {
                    self.tracks.append(track)
                }
                self.scheduleSave()
            }
        }
    }

    func importDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        importDone = 0
        importTotal = urls.count

        let scoped: [(URL, Bool)] = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }

        Task { [weak self] in
            guard let self = self else { return }
            var added: [Track] = []
            var lyricCount = 0
            var failed = 0

            for (position, pair) in scoped.enumerated() {
                let summary = await MediaImporter.importItem(pair.0, into: self.library)
                added.append(contentsOf: summary.addedTracks)
                lyricCount += summary.lyricsCount
                failed += summary.failed
                let done = position + 1
                await MainActor.run { self.importDone = done }
            }

            for (url, accessed) in scoped where accessed {
                url.stopAccessingSecurityScopedResource()
            }

            await MainActor.run {
                self.isImporting = false
                for track in added where !self.tracks.contains(where: { $0.fileName == track.fileName }) {
                    self.tracks.append(track)
                }
                self.scheduleSave()

                var parts: [String] = []
                if !added.isEmpty { parts.append("\(added.count) 首歌曲") }
                if lyricCount > 0 { parts.append("\(lyricCount) 个歌词") }
                if failed > 0 { parts.append("\(failed) 个失败") }
                self.toast = parts.isEmpty ? "没有找到可导入的音频文件" : "导入完成：" + parts.joined(separator: "、")

                if self.currentTrackID == nil, let first = self.tracks.first {
                    self.playTrack(first)
                }
            }
        }
    }

    func removeTrack(_ track: Track) {
        let wasCurrent = currentTrackID == track.id
        let removedIndex = tracks.firstIndex(of: track)

        tracks.removeAll { $0.id == track.id }
        library.deleteTrackFile(track)

        if wasCurrent {
            engine.stop()
            isPlaying = false
            currentTrackID = nil
            elapsed = 0
            duration = 0
            lyrics = []
            currentLyricIndex = nil
            spectrum = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
            spectrumPeaks = spectrum
            updateNowPlaying()
            if let index = removedIndex, !tracks.isEmpty {
                play(index: min(index, tracks.count - 1))
            }
        }
        scheduleSave()
    }

    func move(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func playNext(_ track: Track) {
        guard let from = tracks.firstIndex(of: track) else { return }
        guard from != currentIndex else {
            toast = "「\(track.displayTitle)」正在播放"
            return
        }
        let anchor = currentIndex
        let item = tracks.remove(at: from)
        var insertAt = 0
        if let anchor = anchor {
            insertAt = from < anchor ? anchor : anchor + 1
        }
        insertAt = min(max(0, insertAt), tracks.count)
        tracks.insert(item, at: insertAt)
        scheduleSave()
        toast = "「\(item.displayTitle)」已排到下一首"
    }

    func filteredIndices() -> [Int] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return Array(tracks.indices) }
        return tracks.indices.filter { index in
            let track = tracks[index]
            return track.displayTitle.localizedCaseInsensitiveContains(keyword)
                || track.displayArtist.localizedCaseInsensitiveContains(keyword)
                || track.displayAlbum.localizedCaseInsensitiveContains(keyword)
                || track.fileName.localizedCaseInsensitiveContains(keyword)
        }
    }

    // MARK: - 设置持久化

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func saveNow() {
        let settings = PlayerSettings(
            skin: skin,
            volume: volume,
            repeatMode: repeatMode,
            equalizer: equalizer,
            lyricOffsets: lyricOffsets,
            showLyricsPanel: showLyricsPanel,
            showPlaylistPanel: showPlaylistPanel
        )
        library.saveState(LibrarySnapshot(tracks: tracks, settings: settings))
    }

    // MARK: - 锁屏 / 远程控制

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.next() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.previous() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            DispatchQueue.main.async { self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyAlbumTitle: track.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: max(duration, track.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let image = artworkImage(for: track) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func artworkImage(for track: Track) -> UIImage? {
        if let cached = artworkCache[track.id] {
            return cached
        }
        var image: UIImage?
        if let url = library.artworkURL(for: track), let data = try? Data(contentsOf: url) {
            image = UIImage(data: data)
        }
        if image == nil {
            image = ArtworkFactory.image(for: track, skin: skin)
        }
        if let image = image {
            if artworkCache.count > 12 { artworkCache.removeAll() }
            artworkCache[track.id] = image
        }
        return image
    }

    // MARK: - 音频会话事件

    private func observeSessionNotifications() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

            switch type {
            case .began:
                if self.isPlaying {
                    self.engine.pause()
                    self.isPlaying = false
                    self.updateNowPlaying()
                }
            case .ended:
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).flatMap {
                    AVAudioSession.InterruptionOptions(rawValue: $0)
                }
                if options?.contains(.shouldResume) == true, !self.isPlaying {
                    self.engine.resume()
                    self.isPlaying = true
                    self.updateNowPlaying()
                }
            @unknown default:
                break
            }
        }

        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            if reason == .oldDeviceUnavailable, self.isPlaying {
                self.engine.pause()
                self.isPlaying = false
                self.updateNowPlaying()
            }
        }
    }
}
