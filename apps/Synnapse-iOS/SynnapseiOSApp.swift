import SwiftUI
import Auth
import Features
import Networking
import Models
import AppLifecycle

@main
struct SynnapseiOSApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            // The login gate was removed: the tab view renders
            // unconditionally so the app boots straight into Finance /
            // Life / Advisors. Auth is now a user-initiated action
            // surfaced from Settings (under the More tab), not a
            // startup blocker.
            RootTabView(appModel: appModel)
                .task { await appModel.bootstrapIfNeeded() }
                .onOpenURL { url in
                    // Deep links route through `AppLifecycleService`.
                    // Unrecognised URLs return nil from `parse(url:)` and
                    // are silently dropped — matches the macOS shell.
                    appModel.lifecycle.handle(url: url)
                }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var auth: AuthViewModel
    private(set) var financePersonal: FinancePersonalViewModel
    private(set) var financeAccounts: FinanceAccountsViewModel
    private(set) var financeTransactions: FinanceTransactionsViewModel
    private(set) var financeInvestments: FinanceInvestmentsViewModel
    /// LIFE terminal view model. Single instance owned by the app shell
    /// so the iOS tab and any future deep links share scrollback state.
    let life: LifeViewModel

    // Advisors — financial advisors, personal-life scope.
    private(set) var advisors: AdvisorsListViewModel

    // Settings.
    private(set) var settings: SettingsViewModel

    // Deep-link router + restoration.
    let lifecycle: AppLifecycleService

    /// When true, the VMs are bound to Mock APIs pre-seeded with demo
    /// fixtures so the cockpit renders representative data on first
    /// paint. DEBUG-only; release builds talk to the live server.
    let usesDemoData: Bool

    private let demoFinanceAPI: MockFinanceAPI?
    private let demoLifeAPI: MockLifeAPI?
    private let demoAdvisorsAPI: MockAdvisorsAPI?

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

        #if DEBUG
        let mockFinance = MockFinanceAPI()
        let mockLife = MockLifeAPI()
        let mockAdvisors = MockAdvisorsAPI()
        self.demoFinanceAPI = mockFinance
        self.demoLifeAPI = mockLife
        self.demoAdvisorsAPI = mockAdvisors
        self.usesDemoData = true
        let financeAPI: FinanceAPI = mockFinance
        let lifeAPI: LifeAPI = mockLife
        let advisorsAPI: AdvisorsAPI = mockAdvisors
        #else
        self.demoFinanceAPI = nil
        self.demoLifeAPI = nil
        self.demoAdvisorsAPI = nil
        self.usesDemoData = false
        let financeAPI: FinanceAPI = LiveFinanceAPI(client: client)
        let lifeAPI: LifeAPI = LiveLifeAPI(client: client, serverContractLive: false)
        let advisorsAPI: AdvisorsAPI = LiveAdvisorsAPI(client: client)
        #endif

        self.financePersonal = FinancePersonalViewModel(api: financeAPI)
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)
        self.life = LifeViewModel(api: lifeAPI)

        self.advisors = AdvisorsListViewModel(api: advisorsAPI)

        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())

        self.lifecycle = AppLifecycleService()
    }

    func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await auth.restoreFromStore()
        if let finance = demoFinanceAPI,
           let lifeMock = demoLifeAPI,
           let advisorsMock = demoAdvisorsAPI {
            await DemoData.seed(
                finance: finance,
                life: lifeMock,
                advisors: advisorsMock
            )
            await financePersonal.refresh()
            await financeAccounts.refresh()
            await financeTransactions.refresh()
            await financeInvestments.refresh()
            await life.refresh()
            await advisors.refresh()
        }
        applyConcealBalancesBridge()
    }

    /// Mirrors `settings.concealBalances` into `financePersonal` by
    /// reusing the M5 scene-phase path. Covered by
    /// [[SettingsFinanceBridgeTests]].
    func applyConcealBalancesBridge() {
        if settings.concealBalances {
            financePersonal.scenePhaseDidChange(.inactive)
        }
    }
}

// The previous `RootShell` wrapper switched between `RootTabView` and
// `SignInView` based on `appModel.auth.state`. That wrapper has been
// removed: the iOS app boots straight into `RootTabView`. Auth is now
// a user-initiated action surfaced from Settings (under the More tab).
// `SignInView`, `AuthViewModel`, `SessionStore`, and `LiveSessionAPI`
// stay in the codebase and remain reachable from Settings.

/// Four visible tabs: Finance, Life, Advisors, More (Settings + sign-out).
/// Synnapse is a private-life client; work surfaces from synapse-v2
/// (Spotlight, Approvals, People, Inbox, Sequences, Octagon, Trading
/// Desk) deliberately do not live here.
private struct RootTabView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        TabView {
            FinanceTab(
                personal: appModel.financePersonal,
                accounts: appModel.financeAccounts,
                transactions: appModel.financeTransactions,
                investments: appModel.financeInvestments
            )
            .identity(.cockpitInstrument)
            .tabItem { Label("Finance", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack {
                LifeTerminalView(viewModel: appModel.life)
                    .navigationTitle("Life")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .identity(.terminalAmber)
            .tabItem { Label("Life", systemImage: "terminal") }

            NavigationStack {
                AdvisorsView(viewModel: appModel.advisors)
                    .navigationTitle("Advisors")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .identity(.cockpitInstrument)
            .tabItem { Label("Advisors", systemImage: "bubble.left.and.bubble.right") }

            MoreTab(appModel: appModel)
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}

/// iOS Finance tab: NavigationStack rooted at the Personal screen, with
/// pushed navigation to Accounts / Transactions / Investments.
private struct FinanceTab: View {
    let personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel

    private enum Route: Hashable {
        case accounts, transactions, investments
    }

    var body: some View {
        NavigationStack {
            FinancePersonalView(viewModel: personal)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        NavigationLink(value: Route.accounts) {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        NavigationLink(value: Route.transactions) {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        NavigationLink(value: Route.investments) {
                            Image(systemName: "chart.pie")
                        }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .accounts: FinanceAccountsView(viewModel: accounts)
                    case .transactions: FinanceTransactionsView(viewModel: transactions)
                    case .investments: FinanceInvestmentsView(viewModel: investments)
                    }
                }
        }
    }
}

/// "More" tab. Hosts Settings + any future scalar surfaces. Today it's
/// just a Settings entry — kept as its own tab so the standard iOS
/// "swipe down on More" gesture still works for surfaces we add later.
private struct MoreTab: View {
    let appModel: AppModel

    private enum Route: Hashable {
        case settings
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: Route.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .settings:
                    SettingsForm(settings: appModel.settings, auth: appModel.auth)
                        .identity(.editorial)
                }
            }
        }
    }
}
