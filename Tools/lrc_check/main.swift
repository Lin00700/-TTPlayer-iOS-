// LRC 解析 / 时间轴 / 格式化 的自检程序（只在开发机上跑，不参与 App 构建）。
// swiftc TTPlayer/Core/Track.swift TTPlayer/Core/Equalizer.swift TTPlayer/Playback/Lyrics.swift \
//        Tools/lrc_check/main.swift -o /tmp/lrc_check && /tmp/lrc_check

import Foundation

let sample = """
[ti:测试歌曲]
[ar:某歌手]
[offset:+500]
[00:01.00]第一行
[00:05.20][01:02.50]副歌
[00:09.90]
[00:12.345]最后一行
"""

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("✓ \(label)")
    } else {
        failures += 1
        print("✗ \(label)")
    }
}

let parsed = LRCParser.parse(sample)
expect(parsed.title == "测试歌曲", "读取 [ti:]")
expect(parsed.artist == "某歌手", "读取 [ar:]")
expect(abs(parsed.offset - 0.5) < 0.001, "读取 [offset:+500]")
expect(parsed.lines.count == 5, "多时间戳与空行都切分（得到 \(parsed.lines.count) 行）")
expect(parsed.isTimed, "带时间轴的歌词判定")
expect(abs((parsed.lines.first?.time ?? -1) - 1.0) < 0.001, "首行时间 1.0s")
expect(abs((parsed.lines.last?.time ?? -1) - 12.345) < 0.001, "毫秒时间戳 12.345s")

let activeEarly = LyricsTimeline.activeIndex(lines: parsed.lines, elapsed: 0.6, offset: 0.5)
expect(activeEarly == 0, "offset +0.5s 时 0.6s 命中第一行")
let activeMid = LyricsTimeline.activeIndex(lines: parsed.lines, elapsed: 5.0, offset: 0.5)
expect(activeMid == 1, "5.0s 命中第二行")
let activeLate = LyricsTimeline.activeIndex(lines: parsed.lines, elapsed: 62.3, offset: 0.5)
expect(activeLate == 2, "62.3s 命中 01:02.50 那行")

let plain = LRCParser.parse("第一句\n第二句\n\n第三句")
expect(!plain.isTimed, "纯文本歌词判定为无时间轴")
expect(plain.lines.count == 3, "纯文本保留三行")
expect(LyricsTimeline.activeIndex(lines: plain.lines, elapsed: 10, offset: 0) == nil, "纯文本不产生高亮行")

expect(EqualizerSettings.presets.count == 7, "七套预设")
expect(EqualizerSettings.presets.allSatisfy { $0.gains.count == EqualizerSettings.frequencies.count }, "预设都是 10 段")

expect(TTFormat.time(83.4) == "01:23", "83.4s → 01:23")
expect(TTFormat.time(3725) == "1:02:05", "3725s → 1:02:05")
expect(TTFormat.remaining(10, 100) == "-01:30", "余时 -01:30")
expect(TTFormat.sampleRate(44100) == "44.1 kHz", "采样率读数")
expect(TTFormat.bitrate(320) == "320 kbps", "码率读数")
expect(TTFormat.fileSize(5_242_880) == "5.0 MB", "文件大小读数")

var settings = EqualizerSettings.default
settings.apply(preset: EqualizerSettings.presets[1])
expect(settings.presetName == "流行" && settings.gains[4] == 4, "应用预设")
settings.gains = [1, 2]
settings.normalize()
expect(settings.gains.count == 10 && settings.gains[1] == 2, "normalize 补齐 10 段")

print(failures == 0 ? "ALL OK" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
