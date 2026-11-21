import SwiftUI

struct RootView: View {
    @EnvironmentObject var player: PlayerStore

    private var theme: Theme { player.theme }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        MainWindowView()
                        LyricsWindowView()
                        PlaylistWindowView()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .sheet(isPresented: $player.showEqualizer) {
            EqualizerSheet()
        }
        .sheet(isPresented: $player.showWifi) {
            WifiUploadSheet()
        }
        .overlay(alignment: .bottom) {
            toastLayer
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
