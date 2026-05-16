import SwiftUI
import AppKit
import Features
import Networking

@main
struct SynnapseMacApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Synnapse") {
            RootView()
                .frame(minWidth: 720, minHeight: 480)
                .task { appModel.bootstrapIfNeeded() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .windowList) {
                Button("Show Spotlight") { appModel.toggleSpotlight() }
                    .keyboardShortcut(.space, modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private var bootstrapped = false
    private var spotlightController: SpotlightPanelController?
    private var hotkey: GlobalHotkeyMonitor?

    func bootstrapIfNeeded() {
        guard !bootstrapped else { return }
        bootstrapped = true

        let baseURLString = ProcessInfo.processInfo.environment["SYNNAPSE_API_BASE"]
            ?? "http://localhost:3000/"
        let baseURL = URL(string: baseURLString) ?? URL(string: "http://localhost:3000/")!
        let client = APIClient(
            baseURL: baseURL,
            session: .shared,
            defaultHeaders: ["Accept": "application/json"]
        )
        let api = LiveSpotlightAPI(client: client)
        let viewModel = SpotlightViewModel(api: api)
        let controller = SpotlightPanelController(viewModel: viewModel)
        spotlightController = controller

        let monitor = GlobalHotkeyMonitor { [weak self] in
            self?.spotlightController?.toggle()
        }
        monitor.start()
        hotkey = monitor
    }

    func toggleSpotlight() {
        spotlightController?.toggle()
    }
}
