import SwiftUI

@main
struct SynnapseMacApp: App {
    var body: some Scene {
        WindowGroup("Synnapse") {
            RootView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
