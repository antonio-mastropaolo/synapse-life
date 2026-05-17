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

    var body: some Scene {
        WindowGroup("Synapse") {
            // Single live shell. The previous build painted a static
            // `RootView` preview in the main window and only opened the
            // real surfaces in secondary windows via menu commands —
            // sidebar rows did nothing. The new shell hosts the
            // surviving surfaces directly, switched via the sidebar.
            ZStack(alignment: .top) {
                CockpitShellMac(
                    routing: routing,
                    personal: appModel.financePersonal,
                    accounts: appModel.financeAccounts,
                    transactions: appModel.financeTransactions,
                    investments: appModel.financeInvestments,
                    lifeAPI: appModel.lifeAPI,
                    advisors: appModel.advisors,
                    showsDemoDataFooter: appModel.usesDemoData
                )

                if appModel.commandBar.isPresented {
                    // Dim the background and absorb taps outside the
                    // palette so the user can dismiss with a click.
                    Color.black.opacity(0.30)
                        .ignoresSafeArea()
                        .onTapGesture { appModel.commandBar.close() }
                        .transition(.opacity)

                    CommandBarView(viewModel: appModel.commandBar) { sugg in
                        applySuggestion(sugg)
                        appModel.commandBar.close()
                    }
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: appModel.commandBar.isPresented)
            .frame(minWidth: 960, minHeight: 640)
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
            // secondary windows. Matches the brief's "no extra chrome"
            // direction.
            CommandGroup(after: .toolbar) {
                Button("Ask Synapse") { appModel.commandBar.open() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Finance") { routing.select(.finance(.personal)) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Accounts") { routing.select(.finance(.accounts)) }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Transactions") { routing.select(.finance(.transactions)) }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                Button("Investments") { routing.select(.finance(.investments)) }
                    .keyboardShortcut("5", modifiers: [.command, .shift])
                Button("Life") { routing.select(.life) }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Advisors") { routing.select(.advisors) }
                    .keyboardShortcut("7", modifiers: [.command])
            }
        }

        // No explicit window for the palette — it is overlaid inside
        // the main scene above. `applySuggestion` lives here so the
        // routing VM is in scope.
        Settings {
            // M9 promoted Settings to the full `SettingsScene`. The
            // standard macOS Cmd-, gesture opens this scene for free; no
            // explicit command is needed.
            SettingsScene(settings: appModel.settings, auth: appModel.auth)
        }
    }

    /// Route a command-bar suggestion to the right sidebar destination.
    /// Surface jumps update routing; the other kinds are advisory-only
    /// today (the advisor target lands as a routing.select(.advisors)).
    private func applySuggestion(_ sugg: CommandSuggestion) {
        switch sugg.kind {
        case .surface(let target):
            switch target {
            case .personal:     routing.select(.finance(.personal))
            case .accounts:     routing.select(.finance(.accounts))
            case .transactions: routing.select(.finance(.transactions))
            case .investments:  routing.select(.finance(.investments))
            case .life:         routing.select(.life)
            case .advisors:     routing.select(.advisors)
            case .settings:     break // macOS opens Settings via Cmd-,
            }
        case .savedQuery:
            appModel.commandBar.query = sugg.label
            appModel.commandBar.submit()
        case .askAdvisor:
            routing.select(.advisors)
        }
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

    /// LIFE terminal API. Forward-compat against `/api/life/entries`; the
    /// server has not implemented it yet so the live client returns an
    /// empty stream and the view renders the deterministic boot line.
    let lifeAPI: LifeAPI

    // Advisors — financial advisors, personal-life scope.
    private(set) var advisors: AdvisorsListViewModel

    // Settings.
    private(set) var settings: SettingsViewModel

    // Command bar — global ⌘K palette. Backed by the local Ask stub
    // until /api/ai/ask lands.
    private(set) var commandBar: CommandBarViewModel

    // Deep-link router + restoration.
    let lifecycle: AppLifecycleService

    /// When true, the VMs are bound to Mock APIs pre-seeded with demo
    /// fixtures. DEBUG builds set this so the cockpit renders something
    /// on first paint instead of empty `.idle` states. The sidebar
    /// surfaces a one-line "demo data" footer in this mode.
    let usesDemoData: Bool

    // Handles to the Mock APIs when running in demo mode; `nil` in
    // release wiring. Kept to call `DemoData.seed` from
    // `bootstrapIfNeeded` before the VMs refresh.
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

        // Default: Live APIs against the real synapse-v2 server at
        // baseURL. Set SYNNAPSE_USE_DEMO=1 in the environment to fall
        // back to Mock APIs with pre-seeded demo fixtures.
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

        // Command bar — captures a snapshot of the personal VM each
        // time a query submits, so the Ask stub always has fresh
        // context. Closes over a local reference to dodge the "self
        // used before init" diagnostic.
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

        // Deep-link service. The route handler is installed in
        // `bootstrapIfNeeded` so it can capture `openWindow` from the
        // scene environment via a closure on the model.
        self.lifecycle = AppLifecycleService()
    }

    func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await auth.restoreFromStore()

        // Seed the demo fixtures (when in demo mode) before the surfaces
        // refresh so the first paint isn't an empty `.idle` state.
        if let finance = demoFinanceAPI,
           let life = demoLifeAPI,
           let advisorsAPI = demoAdvisorsAPI {
            await DemoData.seed(
                finance: finance,
                life: life,
                advisors: advisorsAPI
            )
        }

        // Refresh every surface on bootstrap regardless of demo/live so
        // the first paint shows real data even when the user lands on a
        // tab whose `.task` hasn't fired yet.
        await financePersonal.refresh()
        await financeAccounts.refresh()
        await financeTransactions.refresh()
        await financeInvestments.refresh()
        await advisors.refresh()

        // Settings <-> Finance bridge. When the conceal-balances
        // preference is on, forward an inactive scene-phase signal to the
        // finance personal VM so the home screen masks balances even
        // while the app is active.
        applyConcealBalancesBridge()
    }

    /// Mirror `settings.concealBalances` into `financePersonal` by reusing
    /// the existing scene-phase path the M5 VM already exposes. The bridge
    /// lives in the app shell because M9 deliberately did not add a public
    /// setter to FinancePersonalViewModel.
    func applyConcealBalancesBridge() {
        if settings.concealBalances {
            financePersonal.scenePhaseDidChange(.inactive)
        }
    }
}

// The previous `RootShell` wrapper gated the boot path on
// `appModel.auth.state`. That wrapper has been removed: the app boots
// straight into `RootView()`. Auth is now a user-initiated action
// available from Settings (see `SettingsScene` in
// `packages/SynnapseKit/Sources/Features/Settings/SettingsView.swift`).
// `SignInView`, `AuthViewModel`, `SessionStore`, and `LiveSessionAPI`
// remain in the codebase and stay reachable from Settings so they can
// be re-engaged once the server-side endpoint exists.
