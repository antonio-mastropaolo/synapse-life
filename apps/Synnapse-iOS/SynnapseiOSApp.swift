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
    /// Shared FinanceAPI handle so per-account drill-down screens can
    /// spin up their own scoped `FinanceTransactionsViewModel` without
    /// re-deriving which API (live vs mock) the app booted against.
    let financeAPI: FinanceAPI
    /// LIFE terminal view model. Single instance owned by the app shell
    /// so the iOS tab and any future deep links share scrollback state.
    let life: LifeViewModel

    // Advisors — financial advisors, personal-life scope.
    private(set) var advisors: AdvisorsListViewModel

    // Settings.
    private(set) var settings: SettingsViewModel

    // Command bar — opened from the Finance tab toolbar.
    private(set) var commandBar: CommandBarViewModel

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

        let useDemo = ProcessInfo.processInfo.environment["SYNNAPSE_USE_DEMO"] == "1"
        let financeAPI: FinanceAPI
        let lifeAPI: LifeAPI
        let advisorsAPI: AdvisorsAPI
        if useDemo {
            let mockFinance = MockFinanceAPI()
            let mockLife = MockLifeAPI()
            let mockAdvisors = MockAdvisorsAPI()
            self.demoFinanceAPI = mockFinance
            self.demoLifeAPI = mockLife
            self.demoAdvisorsAPI = mockAdvisors
            self.usesDemoData = true
            financeAPI = mockFinance
            lifeAPI = mockLife
            advisorsAPI = mockAdvisors
        } else {
            self.demoFinanceAPI = nil
            self.demoLifeAPI = nil
            self.demoAdvisorsAPI = nil
            self.usesDemoData = false
            financeAPI = LiveFinanceAPI(client: client)
            lifeAPI = LiveLifeAPI(client: client, serverContractLive: false)
            advisorsAPI = LiveAdvisorsAPI(client: client)
        }

        // Hold the API reference so per-account drill-down screens can
        // spin up their own scoped view models. `personalVM` is used by
        // the command bar's context closure below.
        self.financeAPI = financeAPI
        let personalVM = FinancePersonalViewModel(api: financeAPI)
        self.financePersonal = personalVM
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)
        self.life = LifeViewModel(api: lifeAPI)

        self.advisors = AdvisorsListViewModel(api: advisorsAPI)

        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())

        self.commandBar = CommandBarViewModel(
            askAPI: LiveAskAPI(client: client, serverContractLive: false),
            advisorIds: ["financial", "tax", "life"],
            contextProvider: {
                if case .ready(let snap) = personalVM.state {
                    return AskContext(
                        accounts: snap.accounts,
                        recentTransactions: personalVM.recentTransactions
                    )
                }
                return AskContext(accounts: [], recentTransactions: [])
            }
        )

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
        }
        await financePersonal.refresh()
        await financeAccounts.refresh()
        await financeTransactions.refresh()
        await financeInvestments.refresh()
        await life.refresh()
        await advisors.refresh()
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

/// Four visible tabs: Finance, Life, Advisors, Settings.
///
/// The iOS shell deliberately collapses the macOS multi-window product
/// onto a bottom `TabView`. Tab order is canonical: Finance first because
/// it owns the most-used surfaces (net worth, accounts, ledger);
/// Settings last because Apple's HIG places "configuration / account"
/// tabs at the trailing edge.
///
/// Synnapse is a private-life client; work surfaces from synapse-v2
/// (Spotlight, Approvals, People, Inbox, Sequences, Octagon, Trading
/// Desk) deliberately do not live here.
private struct RootTabView: View {
    @Bindable var appModel: AppModel

    /// Identifiers for the four root tabs. We track selection ourselves
    /// (rather than letting `TabView` drive an implicit `Int`) so the
    /// `onChange` handler can fire a selection haptic the instant the
    /// user lands on a new tab. Apple's own tab bar does not haptic on
    /// switch; we add it because every other top-tier finance app on iOS
    /// does, and the absence reads as a missing affordance.
    enum Tab: Hashable {
        case finance, life, advisors, settings
    }

    @State private var selection: Tab = .finance

    var body: some View {
        TabView(selection: $selection) {
            FinanceTab(
                personal: appModel.financePersonal,
                accounts: appModel.financeAccounts,
                transactions: appModel.financeTransactions,
                investments: appModel.financeInvestments,
                financeAPI: appModel.financeAPI,
                commandBar: appModel.commandBar
            )
            .identity(.cockpitInstrument)
            .tabItem { Label("Finance", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(Tab.finance)

            LifeTab(viewModel: appModel.life)
                .identity(.terminalAmber)
                .tabItem { Label("Life", systemImage: "terminal") }
                .tag(Tab.life)

            AdvisorsTab(viewModel: appModel.advisors)
                .identity(.cockpitInstrument)
                .tabItem { Label("Advisors", systemImage: "person.bubble") }
                .tag(Tab.advisors)

            SettingsTab(appModel: appModel)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onChange(of: selection) { _, _ in
            Haptics.tabSwitch()
        }
    }
}

/// iOS Finance tab: NavigationStack rooted at the **Finance Hub** — four
/// large drill-down cards (Personal / Accounts / Transactions /
/// Investments). The hub itself shows a compact net-worth strip so the
/// first paint always communicates the headline KPI.
private struct FinanceTab: View {
    @Bindable var personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel
    let financeAPI: FinanceAPI
    @Bindable var commandBar: CommandBarViewModel

    var body: some View {
        NavigationStack {
            FinanceHubView(
                personal: personal,
                accounts: accounts,
                transactions: transactions,
                investments: investments
            )
            // Command bar overlay — preserved from the AI-UI v2 pass on
            // top of the worktree's 4-tile hub. The sparkles toolbar item
            // opens an `Ask Synapse` sheet that streams across all three
            // advisors with personal-finance context.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        commandBar.open()
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Ask Synapse")
                }
            }
            .sheet(isPresented: $commandBar.isPresented) {
                CommandBarView(viewModel: commandBar) { _ in
                    commandBar.close()
                }
                .padding()
                .presentationDetents([.medium, .large])
            }
            // Per-account drill-down. Anchored at the hub so any push
            // from Accounts (a deeper view in the stack) still resolves
            // — `NavigationStack` walks up its `.navigationDestination`
            // entries until it finds a matching type.
            .navigationDestination(for: FinanceAccount.self) { account in
                AccountDetailView(account: account, financeAPI: financeAPI)
            }
            .navigationDestination(for: Models.Transaction.self) { tx in
                TransactionDetailView(transaction: tx)
            }
            .navigationDestination(for: InvestmentPosition.self) { position in
                PositionDetailView(position: position)
            }
        }
    }
}

/// Life tab. The LIFE terminal is full-bleed: the nav bar is hidden so
/// the amber phosphor reaches the status bar, and the safe area is
/// honoured by the inner `ScrollView` rather than the chrome above it.
private struct LifeTab: View {
    @Bindable var viewModel: LifeViewModel

    var body: some View {
        NavigationStack {
            LifeTerminalView(viewModel: viewModel)
                .navigationBarHidden(true)
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}

/// Advisors tab. The shell owns the `NavigationStack` so deep links from
/// other surfaces (e.g. Spotlight → advisor) can push directly onto it.
private struct AdvisorsTab: View {
    @Bindable var viewModel: AdvisorsListViewModel

    var body: some View {
        NavigationStack {
            AdvisorsView(viewModel: viewModel)
                .navigationTitle("Advisors")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

/// Settings tab. Rooted at the iOS `SettingsForm` (a plain `Form` with
/// native toggles, pickers, and disclosure rows). Auth lives here as a
/// user-initiated action, not as a startup gate.
private struct SettingsTab: View {
    let appModel: AppModel

    var body: some View {
        NavigationStack {
            SettingsForm(settings: appModel.settings, auth: appModel.auth)
                .identity(.editorial)
        }
    }
}
