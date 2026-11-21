import SwiftUI

/// 全屏视觉舞台：把当前视觉播放放大铺满整屏，配曲目信息、当前歌词和传输控制。
struct FullScreenVisualizerView: View {
    @EnvironmentObject var player: PlayerStore
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var theme: Theme { player.theme }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                stageBackground

                VStack(spacing: 0) {
                    topBar

                    Spacer(minLength: 4)

                    stage(size: geo.size)

                    Spacer(minLength: 4)

                    trackInfo
                    lyricArea
                    progressRow
                    transportRow
                    modeRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .background(theme.pageTop)
    }

    // MARK: 背景

    private var stageBackground: some View {
        ZStack {
            theme.pageBackground
            Circle()
                .fill(theme.pageGlow)
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -110, y: -240)
            Circle()
                .fill(theme.accent.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: 130, y: 260)
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.clear, Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text("收起")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(theme.isClassic ? 0.10 : 0.06)))
                .overlay(Capsule().strokeBorder(theme.windowBorder.opacity(0.45), lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text("全屏视觉")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                Text(player.visualMode.title)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer(minLength: 4)

            SkinToggle(theme: theme, skin: player.skin) { style in
                withAnimation(.easeInOut(duration: 0.25)) {
                    player.skin = style
                }
            }
        }
    }

    // MARK: 舞台

    private func stage(size: CGSize) -> some View {
        let height = min(max(180, size.height * 0.36), 340)
        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.26 : 0.48))

            VisualizerView(
                mode: player.visualMode,
                bands: player.spectrum,
                peaks: player.spectrumPeaks,
                theme: theme,
                elapsed: player.elapsed,
                isPlaying: player.isPlaying,
                artwork: player.currentEmbeddedArtwork,
                large: true
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
        }
        .frame(height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.windowBorder.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: theme.shadow, radius: 16, x: 0, y: 8)
        .contentShape(Rectangle())
        .onTapGesture {
            player.cycleVisualMode()
        }
    }

    // MARK: 曲目

    private var trackInfo: some View {
        VStack(spacing: 5) {
            Text(player.currentTrack?.displayTitle ?? "未选择曲目")
                .font(.system(
                    size: 20,
                    weight: .semibold,
                    design: theme.isClassic ? .default : .serif
                ))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 6) {
                Text(player.currentTrack?.displayArtist ?? "从播放列表选一首歌")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                if !player.formatText.isEmpty, player.formatText != "—" {
                    Text(player.formatText)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(theme.textTertiary.opacity(0.45), lineWidth: 0.6)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: 歌词

    private var activeLyric: String? {
        guard let index = player.currentLyricIndex,
              player.lyrics.indices.contains(index) else { return nil }
        let text = player.lyrics[index].text
        return text.isEmpty ? nil : text
    }

    private var nextLyric: String? {
        guard let index = player.currentLyricIndex,
              player.lyrics.indices.contains(index + 1) else { return nil }
        let text = player.lyrics[index + 1].text
        return text.isEmpty ? nil : text
    }

    private var lyricArea: some View {
        VStack(spacing: 4) {
            Text(activeLyric ?? (player.lyrics.isEmpty ? "♪ 纯音乐 / 没有歌词" : "♪ ♪ ♪"))
                .font(.system(
                    size: 15,
                    weight: .semibold,
                    design: theme.isClassic ? .monospaced : .serif
                ))
                .foregroundColor(theme.accent)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)

            Text(nextLyric ?? " ")
                .font(.system(
                    size: 11,
                    weight: .regular,
                    design: theme.isClassic ? .monospaced : .serif
                ))
                .foregroundColor(theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .animation(.easeInOut(duration: 0.22), value: player.currentLyricIndex)
    }

    // MARK: 进度

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

    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(TTFormat.time(displayElapsed))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(width: 42, alignment: .leading)

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
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.top, 4)
    }

    // MARK: 传输

    private var transportRow: some View {
        HStack(spacing: 24) {
            TransportButton(theme: theme, symbol: "backward.fill", size: 46) {
                player.previous()
            }
            TransportButton(
                theme: theme,
                symbol: player.isPlaying ? "pause.fill" : "play.fill",
                size: 68,
                primary: true
            ) {
                player.togglePlayPause()
            }
            TransportButton(theme: theme, symbol: "forward.fill", size: 46) {
                player.next()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: 模式

    private var modeRow: some View {
        HStack(spacing: 6) {
            ForEach(VisualMode.allCases) { mode in
                let selected = player.visualMode == mode
                Button {
                    player.selectVisualMode(mode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 8.5, weight: .bold))
                        Text(mode.shortTitle)
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(selected ? theme.pageBottom : theme.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        Capsule().fill(
                            selected
                                ? AnyShapeStyle(theme.accentSoft.opacity(0.92))
                                : AnyShapeStyle(Color.white.opacity(theme.isClassic ? 0.08 : 0.05))
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            selected ? theme.accentSoft.opacity(0.7) : theme.windowBorder.opacity(0.35),
                            lineWidth: 0.7
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }
}
