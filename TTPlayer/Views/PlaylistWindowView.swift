import SwiftUI

/// 播放列表窗口：搜索、播放、滑动删除、拖动排序、插播。
struct PlaylistWindowView: View {
    @EnvironmentObject var player: PlayerStore
    @State private var showPicker = false
    @State private var editMode: EditMode = .inactive

    private var theme: Theme { player.theme }

    var body: some View {
        TTWindow(
            theme: theme,
            title: "播放列表",
            subtitle: "\(player.tracks.count) 首",
            collapsed: $player.showPlaylistPanel,
            trailing: AnyView(barControls)
        ) {
            VStack(spacing: 8) {
                searchBar
                if player.tracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
                footerBar
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showPicker) {
            AudioDocumentPicker { urls in
                player.importDocuments(urls)
            }
        }
    }

    // MARK: 标题栏

    private var barControls: some View {
        HStack(spacing: 5) {
            Button {
                editMode = editMode.isEditing ? .inactive : .active
            } label: {
                Text(editMode.isEditing ? "完成" : "排序")
                    .font(.system(size: 9.5, weight: .semibold))
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
                showPicker = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("导入")
                        .font(.system(size: 9.5, weight: .semibold))
                }
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

    // MARK: 搜索

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.textTertiary)
            TextField("搜索歌曲、歌手、专辑", text: $player.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundColor(theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !player.searchText.isEmpty {
                Button {
                    player.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.06 : 0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.windowBorder.opacity(0.35), lineWidth: 0.8)
        )
    }

    // MARK: 列表

    private var isSearching: Bool {
        !player.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedTracks: [Track] {
        player.filteredIndices().compactMap { index in
            player.tracks.indices.contains(index) ? player.tracks[index] : nil
        }
    }

    private var trackList: some View {
        List {
            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { pair in
                let position = pair.offset
                let track = pair.element
                row(track, ordinal: position + 1)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            player.removeTrack(track)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
            .onMove { source, destination in
                guard !isSearching else { return }
                player.move(from: source, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .frame(height: 248)
    }

    private func row(_ track: Track, ordinal: Int) -> some View {
        let isCurrent = player.currentTrackID == track.id
        return HStack(spacing: 9) {
            ZStack {
                if isCurrent {
                    PlayingIndicator(theme: theme, active: player.isPlaying)
                } else {
                    Text(String(format: "%02d", ordinal))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                    .foregroundColor(isCurrent ? theme.accent : theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(track.displayArtist)
                        .font(.system(size: 9.5))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                    Text(track.badge)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(theme.textTertiary.opacity(0.45), lineWidth: 0.6)
                        )
                }
            }

            Spacer(minLength: 4)

            Text(TTFormat.time(track.duration))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isCurrent ? theme.rowActive : theme.rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isCurrent ? theme.accent.opacity(0.45) : Color.black.opacity(0.06), lineWidth: 0.7)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            player.playTrack(track)
        }
        .contextMenu {
            Button {
                player.playTrack(track)
            } label: {
                Label("立即播放", systemImage: "play.fill")
            }
            Button {
                player.playNext(track)
            } label: {
                Label("下一首播放", systemImage: "arrow.turn.down.right")
            }
            Button(role: .destructive) {
                player.removeTrack(track)
            } label: {
                Label("从曲库删除", systemImage: "trash")
            }
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(theme.textTertiary)
            Text("曲库还是空的")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(theme.textSecondary)
            Text("从「文件」导入歌曲或整个文件夹，\n或者用 Wi-Fi 传歌从电脑直接拖进来")
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            HStack(spacing: 8) {
                TTSmallButton(title: "导入文件", theme: theme, filled: true) {
                    showPicker = true
                }
                TTSmallButton(title: "Wi-Fi 传歌", theme: theme) {
                    player.showWifi = true
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 248)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.04 : 0.18))
        )
    }

    // MARK: 底栏

    private var footerBar: some View {
        HStack(spacing: 6) {
            TTSmallButton(title: "全部播放", theme: theme, filled: true) {
                if let first = displayedTracks.first ?? player.tracks.first {
                    player.playTrack(first)
                }
            }
            TTSmallButton(title: "Wi-Fi 传歌", theme: theme) {
                player.showWifi = true
            }
            Spacer(minLength: 2)
            Text(isSearching ? "搜索到 \(displayedTracks.count) 首" : (editMode.isEditing ? "拖动把手排序" : "长按可插播"))
                .font(.system(size: 9))
                .foregroundColor(theme.textTertiary)
                .lineLimit(1)
        }
    }
}
