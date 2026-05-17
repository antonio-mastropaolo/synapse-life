import SwiftUI
import AppKit
import Auth
import Features
import Networking
import Models
import DesignSystem
import AppLifecycle

@main
struct SynnapseMacApp: App {

    @State private var appModel = AppModel()
    @State private var routing = RootShellViewModel()
    /// Whether the Ask sheet is currently presented. The keystroke
    /// (`⌘K`) and the legacy command-bar entry points both flip this
    /// flag; the sheet itself is rendered as a centered overlay so it
    /// can use the same focus / dim semantics as the previous
    /// `CommandBarView` while delivering the richer
    /// `IntelligenceAskView` answer surface.
    @State private var isAskPresented: Bool = false

    var body: some Scene {
        WindowGroup("Synapse") {
            ZStack(alignment: .top) {
                CopilotShellMac(
                    routing: routing,
                    personal: appModel.financePersonal,
                    accounts: appModel.financeAccounts,
                    transactions: appModel.financeTransactions,
                    investments: appModel.financeInvestments,
                    lifeAPI: appModel.lifeAPI,
                    advisors: appModel.advisors,
                    dashboard: appModel.dashboard,
                    categories: appModel.categories,
                    digest: appModel.digest,
                    forecast: appModel.forecast,
                    smartAlerts: appModel.smartAlerts,
                    showsDemoDataFooter: appModel.usesDemoData
                )

                if isAskPresented {
                    // Dim and absorb taps so a click outside the sheet
                    // dismisses — same affordance the legacy command
                    // bar used. The new Ask surface itself owns the
                    // dismiss control inside its header.
                    Color.black.opacity(0.30)
                        .ignoresSafeArea()
                        .onTapGesture { closeAsk() }
                        .transition(.opacity)

                    IntelligenceAskView(
                        viewModel: appModel.intelligenceAsk,
                        onCitationTap: { citation in
                            routeCitation(citation)
                        },
                        onDismiss: { closeAsk() }
                    )
                    .padding(.top, 84)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isAskPresented)
            .frame(minWidth: 1080, minHeight: 720)
            .task { await appModel.bootstrapIfNeeded() }
            .onOpenURL { url in
                appModel.lifecycle.handle(url: url)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            // Sidebar keyboard shortcuts. Each command targets the
            // routing VM so the main window updates in place — no
            // secondary windows.
            CommandGroup(after: .toolbar) {
                Button("Ask Synapse") { openAsk() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Dashboard") { routing.select(.dashboard) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Transactions") { routing.select(.transactions) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Accounts") { routing.select(.accounts) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Investments") { routing.select(.investments) }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Life") { routing.select(.life) }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Advisors") { routing.select(.advisors) }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("Categories") { routing.select(.categories) }
                    .keyboardShortcut("8", modifiers: [.command])
                // INTELLIGENCE section
                Button("Weekly Digest") { routing.select(.digest) }
                    .keyboardShortcut("9", modifiers: [.command])
                Button("Forecast") { routing.select(.forecast) }
                    .keyboardShortcut("0", modifiers: [.command])
                Button("Smart Alerts") { routing.select(.smartAlerts) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsScene(settings: appModel.settings, auth: appModel.auth)
        }
    }

    // MARK: - Ask sheet

    private func openAsk() {
        // Refresh the route badge in case the system intelligence
        // availability flipped (e.g. user toggled Apple Intelligence
        // in System Settings between launches).
        isAskPresented = true
    }

    private func closeAsk() {
        appModel.intelligenceAsk.cancel()
        isAskPresented = false
    }

    /// Route an Ask citation chip tap to the matching sidebar
    /// destination. Per the AI++ manifest section 5: transactions and
    /// accounts route through Transactions / Accounts, category chips
    /// land on Categories, and insight chips dismiss the sheet (they
    /// will route to the Insights surface once it lands).
    private func routeCitation(_ citation: AskCitation) {
        switch citation.kind {
        case .transaction, .account:
            routing.select(.transactions)
        case .category:
            routing.select(.categories)
        case .insight:
            break
        }
        closeAsk()
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var auth: AuthViewModel
    private var bootstrapped = false

    private(set) var financePersonal: FinancePersonalViewModel
    private(set) var financeAccounts: FinanceAccountsViewModel
    private(set) var financeTransactions: FinanceTransactionsViewModel
    private(set) var financeInvestments: FinanceInvestmentsViewModel

    /// LIFE terminal API.
    let lifeAPI: LifeAPI

    private(set) var advisors: AdvisorsListViewModel
    private(set) var settings: SettingsViewModel

    /// Inbox of un-reviewed transactions (agent 2). Seeded with the
    /// rich demo data so the Dashboard tab paints a believable 30-row
    /// queue on first launch. When `/api/dashboard/inbox` lands, swap
    /// to an empty VM and call `dashboard.load(...)` from bootstrap.
    private(set) var dashboard: DashboardViewModel

    /// Categories VM — lifted to AppModel so a single instance
    /// survives sidebar selections AND so `bootstrapIfNeeded` can
    /// project the demo / live transactions through it once on
    /// launch (so the surface renders populated pills the first time
    /// the user clicks the Categories row).
    private(set) var categories: CategoriesViewModel

    // AI++ wedge VMs. The reducers are deterministic against the
    // pinned demo data, so the surfaces render representative content
    // even before any server contract exists.
    private(set) var digest: DigestViewModel
    private(set) var forecast: ForecastViewModel
    private(set) var smartAlerts: SmartAlertsViewModel
    private(set) var intelligenceAsk: IntelligenceAskViewModel

    let lifecycle: AppLifecycleService

    let usesDemoData: Bool

    private let demoFinanceAPI: MockFinanceAPI?
    private let demoLifeAPI: MockLifeAPI?
    private let demoAdvisorsAPI: MockAdvisorsAPI?

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

        let personalVM = FinancePersonalViewModel(api: financeAPI)
        self.financePersonal = personalVM
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)
        self.lifeAPI = lifeAPI

        self.advisors = AdvisorsListViewModel(api: advisorsAPI)
        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())

        // Dashboard inbox — seeded with the same demo data the iOS
        // shell uses so the macOS detail pane paints a populated
        // queue on first run.
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

        // Categories — shared VM. Projection happens in
        // `bootstrapIfNeeded` after the dashboard's demo entries are
        // known (a single shared CategoryStore is fine in-process).
        self.categories = CategoriesViewModel(store: CategoryStore())

        // AI++ wedge. Each VM defers to its local stub API until the
        // matching synapse-v2 route lands. Refreshes are kicked off
        // from `bootstrapIfNeeded` once the finance snapshot exists.
        self.digest = DigestViewModel(api: LocalStubDigestAPI())
        self.forecast = ForecastViewModel(api: LocalStubForecastAPI())
        self.smartAlerts = SmartAlertsViewModel()

        // Ask viewmodel — bridges the existing LiveAskAPI through the
        // new IntelligenceRouter shape. The router auto-picks the
        // Apple Intelligence path on supported systems and falls back
        // to the server-style stream otherwise. The on-device branch
        // wraps the server branch for the "wrap until FoundationModels
        // is generally importable" path agent 5 documented.
        let askAPI = LiveAskAPI(client: client, serverContractLive: false)
        let serverRouter = ServerIntelligenceRouter(askAPI: askAPI)
        let router = DefaultIntelligenceRouter(
            appleIntelligence: AppleIntelligenceRouter(underlying: serverRouter),
            server: serverRouter
        )
        self.intelligenceAsk = IntelligenceAskViewModel(
            router: router,
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
           let life = demoLifeAPI,
           let advisorsAPI = demoAdvisorsAPI {
            await DemoData.seed(
                finance: finance,
                life: life,
                advisors: advisorsAPI
            )
        }

        await financePersonal.refresh()
        await financeAccounts.refresh()
        await financeTransactions.refresh()
        await financeInvestments.refresh()
        await advisors.refresh()

        // Project the dashboard's transactions through the Categories
        // VM so the surface paints populated pill rows on first click.
        // The Dashboard's demo data is a richer set than the live
        // finance VM's recent transactions today; once a real server
        // contract lands, swap to `financePersonal.recentTransactions`.
        let dashboardTxs = dashboard.entries.map(\.transaction)
        await categories.project(transactions: dashboardTxs)

        // Once the finance snapshot is in place, kick off the AI++
        // refreshes so the INTELLIGENCE surfaces are populated before
        // the user lands on them.
        refreshIntelligenceSurfaces()

        applyConcealBalancesBridge()
    }

    /// Refresh Digest / Forecast / Smart Alerts against the current
    /// finance snapshot. Called once from bootstrap; future hooks
    /// (week-rollover, account selection) should re-invoke this.
    private func refreshIntelligenceSurfaces() {
        guard case .ready(let snap) = financePersonal.state else { return }
        let tx = financePersonal.recentTransactions
        digest.refresh(accounts: snap.accounts, transactions: tx)
        if let primary = snap.accounts.first(where: { $0.kind == .checking })
            ?? snap.accounts.first {
            forecast.refresh(account: primary, transactions: tx)
        }
        smartAlerts.refresh(accounts: snap.accounts, transactions: tx)
    }

    func applyConcealBalancesBridge() {
        if settings.concealBalances {
            financePersonal.scenePhaseDidChange(.inactive)
        }
    }
}

// The previous `RootShell` wrapper gated the boot path on
// `appModel.auth.state`. That wrapper has been removed: the app boots
// straight into the live shell. Auth is now a user-initiated action
// available from Settings (see `SettingsScene`).
