import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 歌词窗口：自动滚动的 LRC 行、点行跳转、±0.5s 微调、导入 LRC。
struct LyricsWindowView: View {
    @EnvironmentObject var player: PlayerStore
    @State private var showPicker = false

    private var theme: Theme { player.theme }

    var body: some View {
        TTWindow(
            theme: theme,
            title: "歌词",
            subtitle: player.lyricsSource.isEmpty ? "LRC" : player.lyricsSource,
            collapsed: $player.showLyricsPanel,
            trailing: AnyView(barControls)
        ) {
            content
        }
        .sheet(isPresented: $showPicker) {
            LyricsDocumentPicker { url in
                player.importLyrics(from: url)
            }
        }
    }

    // MARK: 标题栏

    private var barControls: some View {
        HStack(spacing: 4) {
            Button {
                player.nudgeLyricOffset(-0.5)
            } label: {
                offsetChip("−0.5")
            }
            .buttonStyle(.plain)

            Text(offsetLabel)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(abs(player.lyricOffset) > 0.05 ? theme.accentSoft : theme.barTextDim)
                .frame(width: 32)

            Button {
                player.nudgeLyricOffset(0.5)
            } label: {
                offsetChip("+0.5")
            }
            .buttonStyle(.plain)

            Button {
                showPicker = true
            } label: {
                Text("导入 LRC")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(theme.barText)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.accent.opacity(0.55))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func offsetChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(theme.barTextDim)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
    }

    private var offsetLabel: String {
        if abs(player.lyricOffset) < 0.05 { return "0.0s" }
        return String(format: "%+.1fs", player.lyricOffset)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if player.lyrics.isEmpty {
            emptyState
        } else {
            lyricsScroll
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "text.quote")
                .font(.system(size: 19, weight: .light))
                .foregroundColor(theme.textTertiary)
            Text(player.currentTrack == nil ? "先选一首歌" : "没有找到这首歌的歌词")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textSecondary)
            Text("把同名 .lrc 放进曲库、或用右上角「导入 LRC」，\n内嵌歌词的歌曲会自动读取")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.05 : 0.20))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        )
    }

    private var lyricsScroll: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.05 : 0.20))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 11) {
                        ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { pair in
                            let index = pair.offset
                            let line = pair.element
                            lyricRow(line, active: player.currentLyricIndex == index)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, 88)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 210)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.13),
                            .init(color: .black, location: 0.87),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: player.currentLyricIndex) { value in
                    guard let value = value, player.lyrics.indices.contains(value) else { return }
                    let id = player.lyrics[value].id
                    withAnimation(.easeInOut(duration: 0.30)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: player.currentTrackID) { _ in
                    guard let first = player.lyrics.first else { return }
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
        .frame(height: 210)
    }

    private func lyricRow(_ line: LyricLine, active: Bool) -> some View {
        Text(line.text.isEmpty ? "♪ ♪ ♪" : line.text)
            .font(.system(
                size: active ? 15 : 12.5,
                weight: active ? .semibold : .regular,
                design: theme.isClassic ? .monospaced : .serif
            ))
            .foregroundColor(active ? theme.accent : theme.textSecondary.opacity(0.7))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                player.seekToLyric(line)
            }
            .animation(.easeInOut(duration: 0.18), value: active)
    }
}

/// 只挑 .lrc / .txt 的文件选择器
struct LyricsDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = []
        if let lrc = UTType(filenameExtension: "lrc") { types.append(lrc) }
        if let txt = UTType(filenameExtension: "txt") { types.append(txt) }
        if types.isEmpty { types.append(.plainText) }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
