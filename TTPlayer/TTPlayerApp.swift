import SwiftUI

@main
struct TTPlayerApp: App {
    @StateObject private var player = PlayerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}
