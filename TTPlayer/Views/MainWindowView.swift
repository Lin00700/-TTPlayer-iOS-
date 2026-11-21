import SwiftUI

/// 主控窗口：LCD 读数 + 实时频谱 + 进度 + 传输控制。
struct MainWindowView: View {
    @EnvironmentObject var player: PlayerStore

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var theme: Theme { player.theme }

    var body: some View {
        TTWindow(
            theme: theme,
            title: "千千静听",
            subtitle: "TTPlayer",
            trailing: AnyView(barButtons)
        ) {
            VStack(spacing: 10) {
                lcd
                spectrumBlock
                seekRow
                transportRow
            }
            .padding(12)
        }
    }

    // MARK: 标题栏右侧

    private var barButtons: some View {
        HStack(spacing: 5) {
            Button {
                player.cycleRepeatMode()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: player.repeatMode.symbol)
                        .font(.system(size: 9, weight: .bold))
                    Text(player.repeatMode.shortTitle)
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(theme.barTextDim)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
            }
            .buttonStyle(.plain)

            Button {
                player.showEqualizer = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 9, weight: .bold))
                    Text("EQ")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(player.equalizer.enabled ? theme.accentSoft : theme.barTextDim)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.lcdGradient)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.lcdBorder, lineWidth: 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(player.formatText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.lcdTop)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(theme.lcdText.opacity(0.88))
                        )
                    Text("\(player.rateText) · \(player.bitrateText)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.lcdDim)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if !player.lyrics.isEmpty {
                        Text("LRC")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.lcdGlow)
                    }
                }

                MarqueeText(
                    text: player.currentTrack?.displayTitle ?? "未选择曲目",
                    fontSize: 17,
                    weight: .semibold,
                    color: theme.lcdText
                )
                .frame(height: 24)

                HStack(spacing: 5) {
                    Text(player.currentTrack?.displayArtist ?? "从播放列表选一首歌")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(theme.lcdDim)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(TTFormat.time(player.elapsed))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.lcdText)
                    Text("/")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.lcdDim)
                    Text(TTFormat.time(displayDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.lcdDim)
                }
            }
            .padding(10)
        }
        .frame(height: 90)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)
        )
    }

    // MARK: 频谱

    private var spectrumBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.18 : 0.42))
            SpectrumView(bands: player.spectrum, peaks: player.spectrumPeaks, theme: theme)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            VStack {
                Spacer()
                Rectangle()
                    .fill(theme.accent.opacity(0.22))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .frame(height: 74)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.lcdBorder.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: 进度

    private var seekRow: some View {
        HStack(spacing: 7) {
            Text(TTFormat.time(displayElapsed))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(width: 40, alignment: .leading)

            Slider(value: progressBinding, in: 0...1, onEditingChanged: { editing in
                if editing {
                    scrubValue = player.progress
                    scrubbing = true
                } else {
                    scrubbing = false
                    if player.duration > 0 {
                        player.seek(to: scrubValue * player.duration)
                    }
                }
            })
            .tint(theme.accent)

            Text(TTFormat.remaining(displayElapsed, displayDuration))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: 传输

    private var transportRow: some View {
        HStack(spacing: 6) {
            Button {
                player.previous()
            } label: {
                transportIcon("backward.fill", width: 34)
            }
            .buttonStyle(.plain)

            Button {
                player.togglePlayPause()
            } label: {
                playButton
            }
            .buttonStyle(.plain)

            Button {
                player.next()
            } label: {
                transportIcon("forward.fill", width: 34)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 2)

            HStack(spacing: 4) {
                Image(systemName: player.volume <= 0.02 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 14)
                Slider(value: $player.volume, in: 0...1)
                    .tint(theme.accent)
                    .frame(width: 58)
            }
        }
    }

    private func transportIcon(_ symbol: String, width: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(theme.textPrimary)
            .frame(width: width, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.thumbTop.opacity(0.55), theme.thumbBottom.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.windowBorder.opacity(0.5), lineWidth: 0.8)
            )
    }

    private var playButton: some View {
        ZStack {
            Circle()
                .fill(theme.accentGradient)
            Circle()
                .strokeBorder(theme.windowBorder.opacity(0.65), lineWidth: 1)
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.pageBottom)
                .offset(x: player.isPlaying ? 0 : 1.5)
        }
        .frame(width: 52, height: 52)
        .shadow(color: theme.shadow, radius: 4, x: 0, y: 2)
    }

    // MARK: 计算

    private var displayDuration: Double {
        if player.duration > 0 { return player.duration }
        return player.currentTrack?.duration ?? 0
    }

    private var displayElapsed: Double {
        if scrubbing { return scrubValue * displayDuration }
        return player.elapsed
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: { scrubbing ? scrubValue : player.progress },
            set: { newValue in scrubValue = newValue }
        )
    }
}
