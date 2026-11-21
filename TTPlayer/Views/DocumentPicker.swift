import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 选歌的两种模式：
/// - `.files`：选文件（可多选），`asCopy: true`，iCloud Drive / 第三方 App 的文件都能稳定拿到本地副本
/// - `.folder`：选整个文件夹，`asCopy: false` + 安全作用域，由导入层用 NSFileCoordinator 逐个协调读取
enum AudioDocumentPickerMode {
    case files
    case folder
}

/// 从「文件」App 选歌 / 选文件夹
struct AudioDocumentPicker: UIViewControllerRepresentable {
    let mode: AudioDocumentPickerMode
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch mode {
        case .files:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.fileTypes, asCopy: true)
            picker.allowsMultipleSelection = true
        case .folder:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.allowsMultipleSelection = true
        }

        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    /// 音频与歌词之外再带上 `public.data`：下载来的文件经常没有扩展名，
    /// 或者后缀和内容不符，选得出来才有机会在导入时按文件头识别
    static var fileTypes: [UTType] {
        var types: [UTType] = [.audio]

        for ext in ["mp3", "m4a", "m4b", "aac", "flac", "wav", "aif", "aiff", "caf", "mp4", "lrc", "txt"] {
            guard let type = UTType(filenameExtension: ext, conformingTo: .data) else { continue }
            if !types.contains(type) {
                types.append(type)
            }
        }

        types.append(.data)
        return types
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else { return }
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

/// 只挑 .lrc / .txt 的文件选择器（同样用 asCopy，避免第三方文件读不到）
struct LyricsDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = []
        for ext in ["lrc", "txt"] {
            guard let type = UTType(filenameExtension: ext, conformingTo: .plainText) else { continue }
            if !types.contains(type) {
                types.append(type)
            }
        }
        if types.isEmpty { types.append(.plainText) }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
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
