import SwiftUI
import AppKit
import Auth
import Features
import Networking
import Models
import DesignSystem

@main
struct SynnapseMacApp: App {

    @State private var appModel = AppModel()

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Synnapse") {
            RootShell(appModel: appModel)
                .frame(minWidth: 720, minHeight: 480)
                .task { await appModel.bootstrapIfNeeded() }
                .toolbar {
                    // Cockpit shell toolbar: a single Spotlight palette
                    // button. ⌘K toggles the panel, matching the M2 hotkey
                    // (and complementing the existing ⌘⇧Space global hotkey).
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            appModel.toggleSpotlight()
                        } label: {
                            Label("Spotlight", systemImage: "command")
                        }
                        .keyboardShortcut("k", modifiers: [.command])
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Approvals", id: "approvals") {
            ApprovalsFlatView(viewModel: appModel.approvals)
                .frame(minWidth: 960, minHeight: 600)
                .identity(.editorial)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Approvals · Tree", id: "approvals-tree") {
            ApprovalsTreeView(viewModel: appModel.approvalsTree)
                .frame(minWidth: 960, minHeight: 600)
                .identity(.editorial)
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

        WindowGroup("People", id: "people") {
            PeopleView(viewModel: appModel.people)
                .frame(minWidth: 1100, minHeight: 640)
                .identity(.editorial)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Inbox", id: "inbox") {
            InboxListView(viewModel: appModel.inbox)
                .frame(minWidth: 1100, minHeight: 640)
                .identity(.editorial)
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

        WindowGroup("Octagon", id: "octagon") {
            OctagonView(viewModel: appModel.octagon)
                .frame(minWidth: 1100, minHeight: 640)
                .identity(.cockpitInstrument)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Trading Desk", id: "trading-desk") {
            TradingDeskView(viewModel: appModel.tradingDesk)
                .frame(minWidth: 1100, minHeight: 640)
                .identity(.cockpitInstrument)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Sequences", id: "sequences") {
            SequencesView(viewModel: appModel.sequences)
                .frame(minWidth: 960, minHeight: 600)
                .identity(.editorial)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .windowList) {
                Button("Show Spotlight") { appModel.toggleSpotlight() }
                    .keyboardShortcut(.space, modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Approvals") { openWindow(id: "approvals") }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Approvals Tree") { openWindow(id: "approvals-tree") }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("Finance") { openWindow(id: "finance") }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Accounts") { openWindow(id: "finance-accounts") }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Life") { openWindow(id: "life") }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("People") { openWindow(id: "people") }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Inbox") { openWindow(id: "inbox") }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Advisors") { openWindow(id: "advisors") }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("Octagon") { openWindow(id: "octagon") }
                    .keyboardShortcut("8", modifiers: [.command])
                Button("Trading Desk") { openWindow(id: "trading-desk") }
                    .keyboardShortcut("9", modifiers: [.command])
                Button("Sequences") { openWindow(id: "sequences") }
                    .keyboardShortcut("0", modifiers: [.command])
            }
        }

        Settings {
            // M9 promoted Settings to the full `SettingsScene`. The
            // standard macOS ⌘, gesture opens this scene for free; no
            // explicit command is needed.
            SettingsScene(settings: appModel.settings, auth: appModel.auth)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var auth: AuthViewModel
    private(set) var spotlight: SpotlightViewModel
    private(set) var approvals: ApprovalsViewModel
    private(set) var approvalsTree: ApprovalsTreeViewModel
    private var bootstrapped = false
    private var spotlightController: SpotlightPanelController?
    private var hotkey: GlobalHotkeyMonitor?

    private(set) var financePersonal: FinancePersonalViewModel
    private(set) var financeAccounts: FinanceAccountsViewModel
    private(set) var financeTransactions: FinanceTransactionsViewModel
    private(set) var financeInvestments: FinanceInvestmentsViewModel

    /// LIFE terminal API. Forward-compat against `/api/life/entries`; the
    /// server has not implemented it yet so the live client returns an
    /// empty stream and the view renders the deterministic boot line.
    let lifeAPI: LifeAPI

    // M7 — People + Inbox.
    private(set) var people: PeopleViewModel
    private(set) var inbox: InboxListViewModel

    // M8 — Advisors + Octagon + Trading Desk.
    private(set) var advisors: AdvisorsListViewModel
    private(set) var octagon: OctagonViewModel
    private(set) var tradingDesk: TradingDeskViewModel

    // M9 — Sequences + Settings.
    private(set) var sequences: SequencesViewModel
    private(set) var settings: SettingsViewModel

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
        let approvalsAPI = LiveApprovalsAPI(client: client)
        self.approvals = ApprovalsViewModel(api: approvalsAPI)
        self.approvalsTree = ApprovalsTreeViewModel(api: approvalsAPI)
        let financeAPI = LiveFinanceAPI(client: client)
        self.financePersonal = FinancePersonalViewModel(api: financeAPI)
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)
        self.lifeAPI = LiveLifeAPI(client: client, serverContractLive: false)

        // M7 wiring.
        self.people = PeopleViewModel(api: LivePeopleAPI(client: client))
        self.inbox = InboxListViewModel(api: LiveInboxAPI(client: client))

        // M8 wiring. `membershipsContractLive: false` keeps Octagon's
        // memberships pane in its forward-compat empty state until the
        // server contract lands. See M8 manifest.
        self.advisors = AdvisorsListViewModel(api: LiveAdvisorsAPI(client: client))
        self.octagon = OctagonViewModel(api: LiveOctagonAPI(
            client: client, membershipsContractLive: false
        ))
        self.tradingDesk = TradingDeskViewModel(api: financeAPI)

        // M9 wiring.
        self.sequences = SequencesViewModel(api: LiveSequencesAPI(client: client))
        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())
    }

    func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await auth.restoreFromStore()
        // The Spotlight panel + global hotkey are always wired, but the
        // panel renders a sign-in prompt when no session exists. We still
        // bring them up at launch so the hotkey is hot from second zero.
        let controller = SpotlightPanelController(viewModel: spotlight, auth: auth)
        spotlightController = controller
        let monitor = GlobalHotkeyMonitor { [weak self] in
            self?.spotlightController?.toggle()
        }
        monitor.start()
        hotkey = monitor

        // M9 settings <-> M5 finance bridge. When the conceal-balances
        // preference is on, forward an inactive scene-phase signal to the
        // finance personal VM so the home screen masks balances even
        // while the app is active. See [[SettingsFinanceBridgeTests]].
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

    func toggleSpotlight() {
        spotlightController?.toggle()
    }
}

/// Top-level shell: shows `SignInView` as a sheet over `RootView` until the
/// `AuthViewModel` reports a session, then drops the sheet.
private struct RootShell: View {
    @Bindable var appModel: AppModel

    private var isSignedIn: Bool {
        if case .signedIn = appModel.auth.state { return true }
        return false
    }

    var body: some View {
        RootView()
            .sheet(isPresented: .constant(!isSignedIn)) {
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
                .frame(minWidth: 480, minHeight: 360)
                .interactiveDismissDisabled(true)
            }
    }
}
