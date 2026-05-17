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
    /// Inbox of un-reviewed transactions. The Copilot-inspired
    /// Dashboard tab is the iOS shell's default; the view model is
    /// seeded with [[DashboardDemoData]] at init so the first paint
    /// is never empty even before the server contract lands.
    private(set) var dashboard: DashboardViewModel
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

    /// Subscriptions surface (replaces the previous ComingSoonView).
    /// Refreshed after demo bootstrap so the More-tab destination
    /// renders detected subscriptions on first push.
    private(set) var subscriptions: SubscriptionsViewModel

    /// Recurrings surface — broader than Subscriptions; surfaces
    /// every detected cadence including bi-weekly payroll and
    /// monthly rent. Persists Confirm / Ignore decisions through
    /// [[RecurringStatusStore]].
    private(set) var recurrings: RecurringsViewModel

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
        // Seed the Dashboard with the rich demo inbox so the tab paints
        // a believable 30-row review queue on first launch. When the
        // server contract for `/api/dashboard/inbox` lands, swap this
        // for an empty VM and call `dashboard.load(...)` from
        // `bootstrapIfNeeded`.
        self.dashboard = DashboardViewModel(
            entries: DashboardDemoData.entries(
                relativeTo: Date(),
                calendar: Calendar.current
            ),
            ledgerTotal: DashboardDemoData.ledgerTotal,
            calendar: Calendar.current,
            referenceDate: Date(),
            locale: .current
        )
        self.life = LifeViewModel(api: lifeAPI)

        self.advisors = AdvisorsListViewModel(api: advisorsAPI)

        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())

        // Subscriptions + Recurrings view models — populated from the
        // finance transactions feed in `bootstrapIfNeeded` once the
        // mock or live API has lent us its data.
        self.subscriptions = SubscriptionsViewModel()
        self.recurrings = RecurringsViewModel()

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

        // Hydrate Subscriptions + Recurrings off the same
        // transaction feed the FinancePersonal VM consumed. The
        // detectors are pure-logic so this is a synchronous step.
        let tx = financePersonal.recentTransactions
        subscriptions.refresh(transactions: tx)
        recurrings.refresh(transactions: tx)

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

/// Five visible tabs (Copilot-inspired reshape, 2026-05-17):
///   Dashboard · Transactions · Cash flow · Investments · More
///
/// The shape mirrors Copilot's bottom rail. The first tab is now the
/// review-queue inbox rather than the finance hub — that matches the
/// product's primary action ("look at what's new and triage") rather
/// than the analytic view ("how much do I have"). Cash flow and
/// Investments are first-class because they're the two surfaces a
/// user opens daily without a triage intent.
///
/// More holds the long tail: Goals, Recurrings, Subscriptions,
/// Categories, Accounts, Personal, Life, Advisors, Settings, plus
/// Sign-in entry. The drill-down list lives in [[MoreTab]].
///
/// Synnapse is a private-life client; work surfaces from synapse-v2
/// (Spotlight, Approvals, People, Inbox, Sequences, Octagon, Trading
/// Desk) deliberately do not live here.
private struct RootTabView: View {
    @Bindable var appModel: AppModel

    /// The five visible tab identifiers. We track selection ourselves
    /// (rather than letting `TabView` drive an implicit `Int`) so the
    /// `onChange` handler can fire a selection haptic the instant the
    /// user lands on a new tab. Apple's own tab bar does not haptic on
    /// switch; we add it because every top-tier finance app on iOS
    /// does, and the absence reads as a missing affordance.
    enum Tab: Hashable {
        case dashboard, transactions, cashflow, investments, more
    }

    @State private var selection: Tab = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            DashboardTab(viewModel: appModel.dashboard)
                .identity(.cockpitInstrument)
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                .tag(Tab.dashboard)

            TransactionsTab(
                viewModel: appModel.financeTransactions,
                financeAPI: appModel.financeAPI
            )
            .identity(.cockpitInstrument)
            .tabItem { Label("Transactions", systemImage: "list.bullet.indent") }
            .tag(Tab.transactions)

            CashFlowTab()
                .identity(.cockpitInstrument)
                .tabItem {
                    Label("Cash flow", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(Tab.cashflow)

            InvestmentsTab(viewModel: appModel.financeInvestments)
                .identity(.cockpitInstrument)
                .tabItem { Label("Investments", systemImage: "briefcase") }
                .tag(Tab.investments)

            MoreTab(appModel: appModel)
                .identity(.cockpitInstrument)
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(Tab.more)
        }
        .onChange(of: selection) { _, _ in
            Haptics.tabSwitch()
        }
    }
}

/// Dashboard tab — the inbox of un-reviewed transactions. The view
/// reads from a single `DashboardViewModel` owned by the AppModel;
/// the navigation stack here only carries through to a future
/// `TransactionDetailView` push when an inbox row is tapped (not yet
/// wired — the row's primary affordance is selection, not navigation).
private struct DashboardTab: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            DashboardView(viewModel: viewModel)
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Transactions tab. The macOS surface is the same `FinanceTransactionsView`;
/// on iOS it owns its own NavigationStack so deep links from the More
/// tab (Categories → filtered transactions) push onto it cleanly.
private struct TransactionsTab: View {
    @Bindable var viewModel: FinanceTransactionsViewModel
    let financeAPI: FinanceAPI

    var body: some View {
        NavigationStack {
            FinanceTransactionsView(viewModel: viewModel)
                .navigationTitle("Transactions")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Models.Transaction.self) { tx in
                    TransactionDetailView(transaction: tx)
                }
        }
    }
}

/// Cash flow tab. Agent 4 owns the surface module
/// (`Features/CashFlow/**`); until that lands we render a placeholder
/// so the tab bar's slot is reserved and tappable without a crash.
/// The placeholder is intentionally honest — "Coming soon" beats a
/// half-built chart in a screenshot review.
private struct CashFlowTab: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(
                title: "Cash flow",
                subtitle: "Monthly inflow / outflow with category mix",
                symbol: "chart.line.uptrend.xyaxis"
            )
            .navigationTitle("Cash flow")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Investments tab — was the fourth card on the old hub; now its
/// own bottom-rail entry.
private struct InvestmentsTab: View {
    @Bindable var viewModel: FinanceInvestmentsViewModel

    var body: some View {
        NavigationStack {
            FinanceInvestmentsView(viewModel: viewModel)
                .navigationTitle("Investments")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: InvestmentPosition.self) { position in
                    PositionDetailView(position: position)
                }
        }
    }
}
