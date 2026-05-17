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

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Synapse") {
            // The login gate was removed: the cockpit shell renders
            // unconditionally so the app boots straight into Finance /
            // Life / Advisors. Auth is now a user-initiated action
            // surfaced from Settings, not a startup blocker.
            RootView(showsDemoDataFooter: appModel.usesDemoData)
                .frame(minWidth: 720, minHeight: 480)
                .task { await appModel.bootstrapIfNeeded() }
                .onOpenURL { url in
                    // Deep links are routed through `AppLifecycleService`.
                    // The handler installed in `bootstrapIfNeeded`
                    // dispatches each link to the matching surface via
                    // `openWindow`. Links that don't parse are dropped
                    // silently — `parse(url:)` returns nil.
                    appModel.lifecycle.handle(url: url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Finance", id: "finance") {
            FinanceShellView(
                personal: appModel.financePersonal,
                accounts: appModel.financeAccounts,
                transactions: appModel.financeTransactions,
                investments: appModel.financeInvestments,
                initialSurface: .personal
            )
            .frame(minWidth: 1100, minHeight: 640)
            .identity(.cockpitInstrument)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Finance · Accounts", id: "finance-accounts") {
            FinanceShellView(
                personal: appModel.financePersonal,
                accounts: appModel.financeAccounts,
                transactions: appModel.financeTransactions,
                investments: appModel.financeInvestments,
                initialSurface: .accounts
            )
            .frame(minWidth: 1100, minHeight: 640)
            .identity(.cockpitInstrument)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Life", id: "life") {
            LifeTerminalScene(api: appModel.lifeAPI)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Advisors", id: "advisors") {
            AdvisorsView(viewModel: appModel.advisors)
                .frame(minWidth: 1100, minHeight: 640)
                .identity(.cockpitInstrument)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Synnapse is a private-life client: Finance, Life,
            // Advisors. The View menu opens each surviving surface in
            // its own window. The system Settings shortcut (Cmd-,)
            // opens the SettingsScene below without an explicit entry.
            CommandGroup(after: .toolbar) {
                Button("Finance") { openWindow(id: "finance") }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Accounts") { openWindow(id: "finance-accounts") }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Life") { openWindow(id: "life") }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Advisors") { openWindow(id: "advisors") }
                    .keyboardShortcut("7", modifiers: [.command])
            }
        }

        Settings {
            // M9 promoted Settings to the full `SettingsScene`. The
            // standard macOS Cmd-, gesture opens this scene for free; no
            // explicit command is needed.
            SettingsScene(settings: appModel.settings, auth: appModel.auth)
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

        // DEBUG: bind every VM to a Mock API and seed it from
        // `bootstrapIfNeeded`. Release: live wiring against the real
        // synapse-v2 server.
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
        self.lifeAPI = lifeAPI

        self.advisors = AdvisorsListViewModel(api: advisorsAPI)

        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())

        // Deep-link service. The route handler is installed in
        // `bootstrapIfNeeded` so it can capture `openWindow` from the
        // scene environment via a closure on the model.
        self.lifecycle = AppLifecycleService()
    }

    func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await auth.restoreFromStore()

        // Seed the demo fixtures before the surfaces refresh so the
        // first paint isn't an empty `.idle` state.
        if let finance = demoFinanceAPI,
           let life = demoLifeAPI,
           let advisorsAPI = demoAdvisorsAPI {
            await DemoData.seed(
                finance: finance,
                life: life,
                advisors: advisorsAPI
            )
            await financePersonal.refresh()
            await financeAccounts.refresh()
            await financeTransactions.refresh()
            await financeInvestments.refresh()
            await advisors.refresh()
        }

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
