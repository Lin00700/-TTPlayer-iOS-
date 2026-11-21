import AVFoundation
import Foundation

struct AudioFileInfo {
    let duration: Double
    let sampleRate: Double
    let channels: Int
    /// true：AVAudioFile 打不开（非标准 MP3 头、后缀和内容不符、异常 VBR/ID3 等），
    /// 这一首走 AVPlayer 兼容通道，10 段 EQ 暂时不生效
    let compatibility: Bool
}

enum AudioEngineError: LocalizedError {
    case notPlayable(String)

    var errorDescription: String? {
        switch self {
        case .notPlayable(let reason):
            return reason
        }
    }
}

/// 播放链：AVAudioPlayerNode → AVAudioUnitEQ(10) → mainMixer，在 EQ 输出上挂 tap 取实时 PCM
/// 喂给频谱分析器。AVAudioFile 读不了的文件自动退回 AVPlayer 兼容通道，功能（播放/暂停/进度/
/// 后台/锁屏/结束切歌）一致，只是 EQ 与真实 FFT 频谱换成按播放状态走的柔和动画。
final class AudioEngineController {
    private enum Route {
        case none
        case engine
        case player
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: EqualizerSettings.frequencies.count)
    private let analyzer = SpectrumAnalyzer()

    private var file: AVAudioFile?
    private var connectedFormat: AVAudioFormat?
    private var durationValue: Double = 0
    private var scheduleBase: Double = 0
    private var pausedTime: Double = 0
    private var generation: Int = 0
    private var playing = false
    private var tapInstalled = false
    private var volumeValue: Float = 0.85
    private var route: Route = .none

    // MARK: 兼容通道（AVPlayer）

    private var avPlayer: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemDurationObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var pendingAutoplay = false

    private let fallbackQueue = DispatchQueue(label: "com.lin.ttplayer.fallback", qos: .userInitiated)
    private var fallbackTicker: DispatchSourceTimer?
    private var fallbackBands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var fallbackPeaks = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var fallbackPhase: Double = 0

    /// 播到文件结尾（自然结束）时回调，主线程
    var onFinished: (() -> Void)?
    /// 每帧频谱回调，音频线程 / 兼容通道的后台队列
    var onSpectrum: (([Float], [Float]) -> Void)?
    /// 兼容通道解码失败时回调，主线程
    var onFailure: ((String) -> Void)?
    /// 兼容通道稍后才解析出真实时长时回调，主线程
    var onDurationResolved: ((Double) -> Void)?

    init() {
        engine.attach(player)
        engine.attach(eqNode)
        eqNode.bypass = true
        player.volume = 1.0
        engine.mainMixerNode.outputVolume = volumeValue

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
    }

    deinit {
        teardownFallback()
    }

    // MARK: - 会话

    func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - 打开文件

    func open(url: URL) throws -> AudioFileInfo {
        route = .none
        teardownFallback()
        player.stop()
        playing = false
        generation += 1

        // 优先走 AVAudioEngine，EQ 与真实频谱都在这一路
        if let info = try? openWithEngine(url: url) {
            return info
        }

        // AVAudioFile 太严格：非标准 MP3 头、后缀和内容不符、某些 VBR/ID3 帧都会被拒，
        // 但同一文件 AVPlayer 往往能正常播，所以整体退回兼容通道
        return try openWithPlayer(url: url)
    }

    private func openWithEngine(url: URL) throws -> AudioFileInfo {
        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0, newFile.length > 0 else {
            throw AudioEngineError.notPlayable("音频数据为空")
        }

        let needsRebuild = connectedFormat == nil
            || connectedFormat?.sampleRate != format.sampleRate
            || connectedFormat?.channelCount != format.channelCount

        if needsRebuild {
            rebuildGraph(format: format)
        } else {
            ensureEngineRunning()
        }

        file = newFile
        durationValue = Double(newFile.length) / format.sampleRate
        scheduleBase = 0
        pausedTime = 0
        analyzer.reset()
        route = .engine

        return AudioFileInfo(
            duration: durationValue,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount),
            compatibility: false
        )
    }

    private func openWithPlayer(url: URL) throws -> AudioFileInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        let audioTracks = asset.tracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioEngineError.notPlayable(Self.unplayableReason(url: url))
        }

        var rate: Double = 0
        var channels: Int = 0
        if let description = audioTracks.first?.formatDescriptions.first {
            let format = description as! CMFormatDescription
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                rate = basic.mSampleRate
                channels = Int(basic.mChannelsPerFrame)
            }
        }
        if !rate.isFinite || rate < 0 { rate = 0 }
        if channels <= 0 { channels = 2 }

        let seconds = asset.duration.seconds
        durationValue = seconds.isFinite && seconds > 0 ? seconds : 0

        // 让 AVAudioEngine 彻底让位，避免它的静音 tap 覆盖兼容通道的频谱
        suspendEngine()
        file = nil

        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        avPlayer.volume = volumeValue

        self.avPlayer = avPlayer
        self.playerItem = item
        route = .player
        scheduleBase = 0
        pausedTime = 0
        analyzer.reset()
        observe(item)

        return AudioFileInfo(
            duration: durationValue,
            sampleRate: rate,
            channels: channels,
            compatibility: true
        )
    }

    /// 给用户一句能看懂的原因
    private static func unplayableReason(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "ncm", "qmc", "qmc0", "qmc3", "qmcflac", "qmcogg", "mflac", "mgg", "kgm", "kgma", "kwm", "xm":
            return "这是带加密的缓存文件（.\(ext)），要先解密成普通音频"
        case "ogg", "opus", "ape", "wv":
            return "暂不支持 .\(ext) 格式"
        case "":
            return "文件里没有可播放的音频轨道（可能是加密文件或后缀与内容不符）"
        default:
            return "文件里没有可播放的音频轨道（后缀 .\(ext) 与内容不符）"
        }
    }

    private func observe(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            DispatchQueue.main.async {
                self?.handleStatus(observed)
            }
        }

        itemDurationObservation = item.observe(\.duration, options: [.initial, .new]) { [weak self] observed, _ in
            DispatchQueue.main.async {
                self?.resolveDuration(observed)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handleFallbackEnded()
        }

        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.failFallback(error?.localizedDescription ?? "解码失败")
        }
    }

    private func handleStatus(_ item: AVPlayerItem) {
        guard route == .player, item === playerItem else { return }
        switch item.status {
        case .readyToPlay:
            resolveDuration(item)
        case .failed:
            failFallback(item.error?.localizedDescription ?? "这个文件没法解码")
        default:
            break
        }
    }

    private func resolveDuration(_ item: AVPlayerItem) {
        guard route == .player, item === playerItem else { return }
        let seconds = item.duration.seconds
        guard seconds.isFinite, seconds > 0 else { return }
        guard abs(seconds - durationValue) > 0.5 else { return }
        durationValue = seconds
        onDurationResolved?(seconds)
    }

    private func failFallback(_ reason: String) {
        playing = false
        pendingAutoplay = false
        stopFallbackTicker()
        onFailure?(reason)
    }

    private func handleFallbackEnded() {
        guard route == .player else { return }
        playing = false
        pendingAutoplay = false
        stopFallbackTicker()
        pausedTime = durationValue
        onFinished?()
    }

    private func rebuildGraph(format: AVAudioFormat) {
        engine.stop()
        if tapInstalled {
            eqNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(eqNode)
        engine.connect(player, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        installTap()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("TTPlayer: engine start failed — \(error.localizedDescription)")
        }
    }

    /// 兼容通道接管时把引擎停掉、拆掉 tap，之后回到引擎通道会重新建图
    private func suspendEngine() {
        engine.stop()
        if tapInstalled {
            eqNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        connectedFormat = nil
    }

    private func installTap() {
        guard !tapInstalled else { return }
        eqNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            let bands = self.analyzer.process(buffer: buffer)
            let peaks = self.analyzer.peaks
            self.onSpectrum?(bands, peaks)
        }
        tapInstalled = true
    }

    // MARK: - 传输控制

    func play(from seconds: Double) {
        activateSession()
        switch route {
        case .engine:
            schedule(from: seconds, autoplay: true)
        case .player:
            playFallback(from: seconds)
        case .none:
            break
        }
    }

    func pause() {
        guard playing || pendingAutoplay else { return }
        switch route {
        case .engine:
            pausedTime = currentTime
            player.pause()
        case .player:
            pausedTime = currentTime
            pendingAutoplay = false
            avPlayer?.pause()
            stopFallbackTicker()
        case .none:
            break
        }
        playing = false
    }

    func resume() {
        switch route {
        case .engine:
            guard file != nil else { return }
            activateSession()
            ensureEngineRunning()
            if !playing {
                player.play()
                playing = true
            }
        case .player:
            guard avPlayer != nil else { return }
            startFallbackPlayback()
        case .none:
            return
        }
    }

    func seek(to seconds: Double) {
        switch route {
        case .engine:
            let autoplay = playing
            schedule(from: seconds, autoplay: autoplay)
        case .player:
            guard let avPlayer = avPlayer else { return }
            let clamped = max(0, durationValue > 0 ? min(seconds, durationValue) : seconds)
            pausedTime = clamped
            avPlayer.seek(
                to: CMTime(seconds: clamped, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            if !playing {
                avPlayer.pause()
            }
        case .none:
            break
        }
    }

    func stop() {
        switch route {
        case .engine:
            player.stop()
        case .player:
            avPlayer?.pause()
            avPlayer?.seek(to: CMTime(seconds: 0, preferredTimescale: 600))
            stopFallbackTicker()
        case .none:
            break
        }
        playing = false
        pendingAutoplay = false
        generation += 1
        scheduleBase = 0
        pausedTime = 0
        analyzer.reset()
        let silent = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
        onSpectrum?(silent, silent)
    }

    func setVolume(_ value: Float) {
        volumeValue = min(1, max(0, value))
        engine.mainMixerNode.outputVolume = volumeValue
        avPlayer?.volume = volumeValue
    }

    func apply(equalizer settings: EqualizerSettings) {
        eqNode.bypass = !settings.enabled
        eqNode.globalGain = min(12, max(-12, settings.preamp))
        for (index, band) in eqNode.bands.enumerated() where index < EqualizerSettings.frequencies.count {
            band.filterType = .parametric
            band.frequency = EqualizerSettings.frequencies[index]
            band.bandwidth = 1.0
            band.gain = min(12, max(-12, settings.gains[index]))
            band.bypass = false
        }
    }

    // MARK: - 状态

    var isPlaying: Bool { playing }

    var isLoaded: Bool { route != .none }

    var isFallback: Bool { route == .player }

    var duration: Double { durationValue }

    var currentTime: Double {
        switch route {
        case .engine:
            guard playing,
                  let nodeTime = player.lastRenderTime,
                  let playerTime = player.playerTime(forNodeTime: nodeTime) else {
                return pausedTime
            }
            let time = scheduleBase + Double(playerTime.sampleTime) / playerTime.sampleRate
            return min(durationValue, max(0, time))
        case .player:
            guard let avPlayer = avPlayer else { return pausedTime }
            let seconds = avPlayer.currentTime().seconds
            guard seconds.isFinite else { return pausedTime }
            if durationValue > 0 {
                return min(durationValue, max(0, seconds))
            }
            return max(0, seconds)
        case .none:
            return pausedTime
        }
    }

    // MARK: - 兼容通道内部

    private func playFallback(from seconds: Double) {
        guard let avPlayer = avPlayer else { return }
        let clamped = max(0, durationValue > 0 ? min(seconds, durationValue) : seconds)
        pausedTime = clamped
        pendingAutoplay = true
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.route == .player, self.pendingAutoplay else { return }
                self.startFallbackPlayback()
            }
        }
    }

    private func startFallbackPlayback() {
        guard let avPlayer = avPlayer else { return }
        activateSession()
        avPlayer.play()
        playing = true
        pendingAutoplay = false
        startFallbackTicker()
    }

    private func teardownFallback() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        itemDurationObservation?.invalidate()
        itemDurationObservation = nil
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
            endObserver = nil
        }
        if let token = failObserver {
            NotificationCenter.default.removeObserver(token)
            failObserver = nil
        }
        avPlayer?.pause()
        avPlayer = nil
        playerItem = nil
        pendingAutoplay = false
        stopFallbackTicker()
    }

    // MARK: 兼容通道的频谱动画

    private func startFallbackTicker() {
        guard fallbackTicker == nil else { return }
        fallbackPhase = 0
        let timer = DispatchSource.makeTimerSource(queue: fallbackQueue)
        timer.schedule(deadline: .now() + .milliseconds(60), repeating: .milliseconds(60))
        timer.setEventHandler { [weak self] in
            self?.advanceFallbackSpectrum()
        }
        timer.resume()
        fallbackTicker = timer
    }

    private func stopFallbackTicker() {
        fallbackTicker?.cancel()
        fallbackTicker = nil
    }

    /// AVPlayer 拿不到 PCM，就用播放状态合成一条有起有落、低频更饱满的频谱，
    /// 让面板在兼容模式下也不是死水
    private func advanceFallbackSpectrum() {
        guard playing, route == .player else { return }
        fallbackPhase += 0.11
        let phase = fallbackPhase

        for band in 0..<SpectrumAnalyzer.bandCount {
            let tilt = powf(0.93, Float(band))
            let wobble = 0.52 + 0.48 * Float(sin(phase * (0.65 + Double(band) * 0.13) + Double(band) * 0.9))
            let jitter = Float.random(in: -0.06...0.06)
            let pulse: Float = band < 3 ? Float(max(0, sin(phase * 2.4))) * 0.20 : 0
            var level = tilt * (0.30 + 0.62 * wobble) + jitter + pulse
            level = min(1, max(0.015, level))
            fallbackBands[band] = fallbackBands[band] * 0.55 + level * 0.45
            let peak = max(fallbackBands[band], fallbackPeaks[band] - 0.02)
            fallbackPeaks[band] = peak > 0.002 ? peak : 0
        }

        onSpectrum?(fallbackBands, fallbackPeaks)
    }

    // MARK: - 私有（引擎通道）

    private func schedule(from seconds: Double, autoplay: Bool) {
        guard let file = file else { return }
        player.stop()
        generation += 1
        let token = generation
        let sampleRate = file.processingFormat.sampleRate
        let clamped = max(0, min(seconds, durationValue))
        let startFrame = AVAudioFramePosition(clamped * sampleRate)
        let available = max(0, file.length - startFrame)
        scheduleBase = Double(startFrame) / sampleRate
        pausedTime = scheduleBase

        guard available > 0 else {
            playing = false
            return
        }

        player.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(available),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token else { return }
                self.playing = false
                self.pausedTime = self.durationValue
                self.onFinished?()
            }
        }

        if autoplay {
            ensureEngineRunning()
            player.play()
            playing = true
        } else {
            playing = false
        }
    }

    private func ensureEngineRunning() {
        activateSession()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                NSLog("TTPlayer: engine restart failed — \(error.localizedDescription)")
            }
        }
    }
}
