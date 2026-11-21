import SwiftUI

@main
struct TTPlayerApp: App {
    @StateObject private var player = PlayerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
                // 「文件」里点开歌曲 / 长按「用千千静听打开」，或微信、QQ 的「其他应用打开」
                .onOpenURL { url in
                    player.importIncomingFiles([url])
                }
        }
    }
}
