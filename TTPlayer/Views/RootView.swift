import SwiftUI

struct RootView: View {
    @EnvironmentObject var player: PlayerStore

    private var theme: Theme { player.theme }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    layout(size: geo.size)
                }
            }
        }
        .sheet(isPresented: $player.showEqualizer) {
            EqualizerSheet()
        }
        .sheet(isPresented: $player.showWifi) {
            WifiUploadSheet()
        }
        .fullScreenCover(isPresented: $player.showFullScreenVisual) {
            FullScreenVisualizerView()
                .environmentObject(player)
        }
        .overlay(alignment: .bottom) {
            toastLayer
        }
        .overlay(alignment: .top) {
            importBanner
        }
        .onChange(of: player.toast) { value in
            guard let value = value else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if player.toast == value {
                    player.toast = nil
                }
            }
        }
    }

    // MARK: 主布局

    /// 播放列表吃满剩下的高度（不再在底部留一条空档）；
    /// 歌词优先拿舒服的高度，空间不够时先它让位，再不行就退回可滚动布局（SE 这类小屏）。
    @ViewBuilder
    private func layout(size: CGSize) -> some View {
        let spacing: CGFloat = 10
        let usable = max(0, size.height - 6 - 10)
        let mainEstimate: CGFloat = 352          // 主窗口的自然高度，只用来估分，实际靠 flexible frame 收尾
        let lyricsCeiling: CGFloat = 196
        let lyricsFloor: CGFloat = 128
        let playlistMin: CGFloat = 236
        let playlistFloor: CGFloat = 200         // 低于这个高度就让整屏滚动，播放列表回到固定高度

        let free = max(0, usable - mainEstimate - spacing * 2)   // 歌词 + 播放列表 可用的高度
        let lyricsHeight = min(lyricsCeiling, max(lyricsFloor, free - playlistMin))
        let lyricsChrome = player.showLyricsPanel ? lyricsHeight : 27
        let playlistSpace = free - lyricsChrome
        let fills = playlistSpace >= playlistFloor

        if fills {
            windowStack(spacing: spacing, lyricsHeight: lyricsHeight, fills: true)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                windowStack(spacing: spacing, lyricsHeight: lyricsCeiling, fills: false)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func windowStack(spacing: CGFloat, lyricsHeight: CGFloat, fills: Bool) -> some View {
        VStack(spacing: spacing) {
            MainWindowView()
            LyricsWindowView(contentHeight: lyricsHeight)
            PlaylistWindowView(fillsHeight: fills)
        }
    }

    // MARK: 背景

    private var background: some View {
        ZStack {
            theme.pageBackground
            Circle()
                .fill(theme.pageGlow)
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: -120, y: -260)
            Circle()
                .fill(theme.accent.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 140, y: 240)
            LinearGradient(
                colors: [Color.white.opacity(0.03), Color.clear, Color.black.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("千千静听")
                    .font(.system(
                        size: 17,
                        weight: .bold,
                        design: theme.isClassic ? .default : .serif
                    ))
                    .foregroundColor(theme.textPrimary)
                Text("本地音乐 · TTPlayer")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer(minLength: 6)

            SkinToggle(theme: theme, skin: player.skin) { style in
                withAnimation(.easeInOut(duration: 0.25)) {
                    player.skin = style
                }
            }

            TTIconButton(systemName: "wifi", theme: theme) {
                player.showWifi = true
            }

            TTIconButton(
                systemName: "slider.vertical.3",
                theme: theme,
                active: player.equalizer.enabled
            ) {
                player.showEqualizer = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: 导入进度

    private var importBanner: some View {
        Group {
            if player.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(theme.accentSoft)
                    Text("正在导入 \(player.importDone)/\(max(player.importTotal, 1))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(Color.black.opacity(theme.isClassic ? 0.55 : 0.7))
                )
                .overlay(
                    Capsule().strokeBorder(theme.accent.opacity(0.45), lineWidth: 0.8)
                )
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: player.isImporting)
    }

    // MARK: 提示

    private var toastLayer: some View {
        Group {
            if let toast = player.toast {
                ToastView(theme: theme, message: toast)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: player.toast)
    }
}
