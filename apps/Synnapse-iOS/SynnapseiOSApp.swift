import SwiftUI
import Auth
import Features
import Networking
import Models

@main
struct SynnapseiOSApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootShell(appModel: appModel)
                .task { await appModel.bootstrapIfNeeded() }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var auth: AuthViewModel
    private(set) var spotlight: SpotlightViewModel
    private var bootstrapped = false

    init() {
        let baseURLString = ProcessInfo.processInfo.environment["SYNNAPSE_API_BASE"]
            ?? "http://localhost:3000/"
        let baseURL = URL(string: baseURLString) ?? URL(string: "http://localhost:3000/")!
        let store = SessionStore()
        let sessionAPI = LiveSessionAPI(
            baseURL: baseURL,
            session: .shared,
            serverContractLive: false
        )
        self.auth = AuthViewModel(api: sessionAPI, store: store)
        let client = APIClient(
            baseURL: baseURL,
            session: .shared,
            defaultHeaders: ["Accept": "application/json"]
        )
        self.spotlight = SpotlightViewModel(api: LiveSpotlightAPI(client: client))
    }

    func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await auth.restoreFromStore()
    }
}

private struct RootShell: View {
    @Bindable var appModel: AppModel

    var body: some View {
        switch appModel.auth.state {
        case .signedIn:
            RootTabView(spotlight: appModel.spotlight, auth: appModel.auth)
        case .signedOut, .error:
            SignInView(
                onComplete: { result in
                    Task {
                        switch result {
                        case .success(let cred):
                            await appModel.auth.signIn(with: cred)
                        case .failure:
                            break
                        }
                    }
                }
            )
            .identity(.editorial)
        case .signingIn:
            ZStack { ProgressView() }
        }
    }
}

private struct RootTabView: View {
    let spotlight: SpotlightViewModel
    let auth: AuthViewModel

    var body: some View {
        TabView {
            SpotlightView(viewModel: spotlight)
                .identity(.editorial)
                .tabItem { Label("Spotlight", systemImage: "sparkles") }

            PlaceholderTab(title: "Finance", system: "chart.line.uptrend.xyaxis")
                .tabItem { Label("Finance", systemImage: "chart.line.uptrend.xyaxis") }

            PlaceholderTab(title: "Life", system: "circle.grid.2x2")
                .tabItem { Label("Life", systemImage: "circle.grid.2x2") }

            PlaceholderTab(title: "Approvals", system: "checkmark.seal")
                .tabItem { Label("Approvals", systemImage: "checkmark.seal") }

            MoreTab(auth: auth)
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let system: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 8) {
                    Image(systemName: system)
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                    Text("Coming soon")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
        }
    }
}

private struct MoreTab: View {
    let auth: AuthViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}
