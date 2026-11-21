import Accelerate
import AVFoundation
import Foundation

/// 20 段实时频谱。取 AVAudioEngine tap 的 PCM 缓冲做 2048 点实数 FFT，
/// 按对数频率切成 20 段，快速起、缓慢落，做出千千静听那种“顶一下就慢慢掉”的观感。
final class SpectrumAnalyzer {
    static let bandCount = 20

    private let fftSize = 2048
    private let halfSize = 1024
    private let log2n: vDSP_Length = 11

    private var setup: FFTSetup?
    private let realPtr: UnsafeMutablePointer<Float>
    private let imagPtr: UnsafeMutablePointer<Float>
    private let magPtr: UnsafeMutablePointer<Float>
    private let windowPtr: UnsafeMutablePointer<Float>

    private var bandRanges: [(Int, Int)] = []
    private var smoothed = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var peakValues = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var peakVelocity = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var lastSampleRate: Double = 0

    init() {
        realPtr = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        imagPtr = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        magPtr = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        windowPtr = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)

        realPtr.initialize(repeating: 0, count: fftSize)
        imagPtr.initialize(repeating: 0, count: halfSize)
        magPtr.initialize(repeating: 0, count: halfSize)
        windowPtr.initialize(repeating: 0, count: fftSize)

        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        vDSP_hann_window(windowPtr, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        rebuildRanges(sampleRate: 44100)
    }

    deinit {
        if let setup = setup {
            vDSP_destroy_fftsetup(setup)
        }
        realPtr.deinitialize(count: fftSize)
        imagPtr.deinitialize(count: halfSize)
        magPtr.deinitialize(count: halfSize)
        windowPtr.deinitialize(count: fftSize)
        realPtr.deallocate()
        imagPtr.deallocate()
        magPtr.deallocate()
        windowPtr.deallocate()
    }

    var peaks: [Float] { peakValues }

    /// 处理一帧 PCM，返回平滑之后的 20 段能量（0…1）。
    @discardableResult
    func process(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return smoothed }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return smoothed }

        let channels = max(1, Int(buffer.format.channelCount))
        let sampleRate = buffer.format.sampleRate
        if lastSampleRate == 0 || abs(sampleRate - lastSampleRate) > 0.5 {
            rebuildRanges(sampleRate: sampleRate)
        }

        let count = min(frameLength, fftSize)
        for index in 0..<count {
            var value: Float = 0
            for channel in 0..<channels {
                value += channelData[channel][index]
            }
            realPtr[index] = value / Float(channels)
        }
        if count < fftSize {
            vDSP_vclr(realPtr.advanced(by: count), 1, vDSP_Length(fftSize - count))
        }

        vDSP_vmul(realPtr, 1, windowPtr, 1, realPtr, 1, vDSP_Length(fftSize))
        vDSP_vclr(imagPtr, 1, vDSP_Length(halfSize))
        vDSP_vclr(magPtr, 1, vDSP_Length(halfSize))

        guard let setup = setup else { return smoothed }

        var split = DSPSplitComplex(realp: realPtr, imagp: imagPtr)
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, magPtr, 1, vDSP_Length(halfSize))

        for band in 0..<SpectrumAnalyzer.bandCount {
            let range = bandRanges[band]
            var peak: Float = 0
            if range.1 > range.0 {
                for bin in range.0..<range.1 {
                    peak = max(peak, magPtr[bin])
                }
            }
            let db = 20 * log10f(peak + 1e-6)
            var level = (db + 64) / 64          // -64dB…0dB → 0…1
            level = min(1, max(0, level))
            level = powf(level, 0.8)

            let previous = smoothed[band]
            smoothed[band] = level > previous ? level : previous * 0.84 + level * 0.16

            if smoothed[band] >= peakValues[band] {
                peakValues[band] = smoothed[band]
                peakVelocity[band] = 0
            } else {
                peakVelocity[band] += 0.0012
                peakValues[band] = max(smoothed[band], peakValues[band] - peakVelocity[band])
            }
        }

        return smoothed
    }

    func reset() {
        for index in 0..<SpectrumAnalyzer.bandCount {
            smoothed[index] = 0
            peakValues[index] = 0
            peakVelocity[index] = 0
        }
    }

    private func rebuildRanges(sampleRate: Double) {
        lastSampleRate = sampleRate
        let nyquist = max(1, sampleRate / 2)
        let minFrequency = 40.0
        let maxFrequency = min(16000.0, nyquist * 0.94)
        let ratio = maxFrequency / minFrequency

        var ranges: [(Int, Int)] = []
        for band in 0..<SpectrumAnalyzer.bandCount {
            let lowFrequency = minFrequency * pow(ratio, Double(band) / Double(SpectrumAnalyzer.bandCount))
            let highFrequency = minFrequency * pow(ratio, Double(band + 1) / Double(SpectrumAnalyzer.bandCount))
            var low = Int(lowFrequency / nyquist * Double(halfSize))
            var high = Int(highFrequency / nyquist * Double(halfSize))
            low = max(1, min(halfSize - 1, low))
            high = max(low + 1, min(halfSize, high))
            ranges.append((low, high))
        }
        bandRanges = ranges
    }
}
