import AVFoundation
import Foundation

struct AudioFileInfo {
    let duration: Double
    let sampleRate: Double
    let channels: Int
}

/// AVAudioEngine 播放链：AVAudioPlayerNode → AVAudioUnitEQ(10) → mainMixer，
/// 在 EQ 输出上挂 tap 取实时 PCM 喂给频谱分析器。
final class AudioEngineController {
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

    /// 播到文件结尾（自然结束）时回调，主线程
    var onFinished: (() -> Void)?
    /// 每帧频谱回调，音频线程
    var onSpectrum: (([Float], [Float]) -> Void)?

    init() {
        engine.attach(player)
        engine.attach(eqNode)
        eqNode.bypass = true
        player.volume = 1.0
        engine.mainMixerNode.outputVolume = volumeValue

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
    }

    // MARK: - 会话

    func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - 打开文件

    func open(url: URL) throws -> AudioFileInfo {
        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat

        player.stop()
        playing = false
        generation += 1

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

        return AudioFileInfo(
            duration: durationValue,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount)
        )
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
        schedule(from: seconds, autoplay: true)
    }

    func pause() {
        guard playing else { return }
        pausedTime = currentTime
        player.pause()
        playing = false
    }

    func resume() {
        guard file != nil else { return }
        activateSession()
        ensureEngineRunning()
        if !playing {
            player.play()
            playing = true
        }
    }

    func seek(to seconds: Double) {
        let autoplay = playing
        schedule(from: seconds, autoplay: autoplay)
    }

    func stop() {
        player.stop()
        playing = false
        generation += 1
        scheduleBase = 0
        pausedTime = 0
        analyzer.reset()
    }

    func setVolume(_ value: Float) {
        volumeValue = min(1, max(0, value))
        engine.mainMixerNode.outputVolume = volumeValue
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

    var isLoaded: Bool { file != nil }

    var duration: Double { durationValue }

    var currentTime: Double {
        guard playing,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return pausedTime
        }
        let time = scheduleBase + Double(playerTime.sampleTime) / playerTime.sampleRate
        return min(durationValue, max(0, time))
    }

    // MARK: - 私有

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
