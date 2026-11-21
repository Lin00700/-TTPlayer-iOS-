import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Wi-Fi 传歌面板：二维码、地址、复制、上传记录与说明。
struct WifiUploadSheet: View {
    @EnvironmentObject var player: PlayerStore
    @Environment(\.dismiss) private var dismiss

    private var theme: Theme { player.theme }

    var body: some View {
        WifiSheetContent(
            server: player.wifi,
            theme: theme,
            trackCount: player.tracks.count,
            onClose: { dismiss() }
        )
    }
}

private struct WifiSheetContent: View {
    @ObservedObject var server: WifiUploadServer
    let theme: Theme
    let trackCount: Int
    let onClose: () -> Void

    @State private var copied = false

    var body: some View {
        ZStack {
            theme.pageBackground.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    addressCard
                    if !server.uploads.isEmpty {
                        uploadsCard
                    }
                    tipsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if !server.isRunning {
                server.start()
            }
        }
        .onDisappear {
            server.stop()
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Wi-Fi 传歌")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text(server.isRunning ? "服务已开启" : "服务未开启")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(server.isRunning ? theme.accent : theme.textTertiary)
            }
            Spacer(minLength: 4)
            Button {
                server.toggle()
            } label: {
                Text(server.isRunning ? "停止" : "启动")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(server.isRunning ? theme.accent : theme.pageBottom)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(server.isRunning ? Color.white.opacity(0.06) : theme.accentSoft.opacity(0.9))
                    )
                    .overlay(
                        Capsule().strokeBorder(theme.windowBorder.opacity(0.4), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 地址卡片

    private var addressCard: some View {
        VStack(spacing: 14) {
            if let address = server.address {
                QRCodeView(text: address)
                    .frame(width: 168, height: 168)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
                    )

                Text(address)
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = address
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .bold))
                            Text(copied ? "已复制" : "复制地址")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(
                            Capsule().fill(Color.white.opacity(0.07))
                        )
                        .overlay(Capsule().strokeBorder(theme.windowBorder.opacity(0.45), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)

                    Text("用电脑/手机的浏览器打开，或直接扫码")
                        .font(.system(size: 9.5))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(2)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(theme.textTertiary)
                    Text(server.lastError ?? "正在启动服务…")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                    TTSmallButton(title: "重新启动", theme: theme, filled: true) {
                        server.stop()
                        server.start()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 168)
            }

            HStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                Text("手机曲库 \(trackCount) 首 · 已收到 \(server.receivedCount) 个文件")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.10 : 0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.windowBorder.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: 上传记录

    private var uploadsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("刚刚收到")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            ForEach(server.uploads.prefix(6)) { record in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(theme.accent)
                    Text(record.name)
                        .font(.system(size: 11.5))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if record.bytes > 0 {
                        Text(TTFormat.fileSize(Int64(record.bytes)))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: 说明

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("使用说明")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            tip("1", "手机和电脑连同一个 Wi-Fi，首次使用允许「本地网络」权限。")
            tip("2", "浏览器打开上面的地址，把 MP3 / FLAC / M4A / WAV / AAC 拖进上传框。")
            tip("3", "歌词用同名 .lrc 一起上传，播放时会自动匹配。")
            tip("4", "传完回到 App，播放列表会自动刷新；也可以从「文件」App 的千千静听文件夹里看到。")
            tip("5", "关掉这个面板后服务会停止，安全省电。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func tip(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accent)
                .frame(width: 14, height: 14)
                .background(Circle().fill(theme.accent.opacity(0.16)))
            Text(text)
                .font(.system(size: 10.5))
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 二维码

struct QRCodeView: View {
    let text: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.85))
            }
        }
        .onAppear {
            image = QRCodeRenderer.image(from: text)
        }
        .onChange(of: text) { newValue in
            image = QRCodeRenderer.image(from: newValue)
        }
    }
}

enum QRCodeRenderer {
    static func image(from text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
