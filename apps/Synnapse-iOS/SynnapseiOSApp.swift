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
            RootShell(appModel: appModel)
                .task { await appModel.bootstrapIfNeeded() }
                .onOpenURL { url in
                    // Deep links are routed through `AppLifecycleService`.
                    // Unrecognised URLs return nil from `parse(url:)` and
                    // are silently dropped — matches the macOS shell's
                    // behaviour.
                    appModel.lifecycle.handle(url: url)
                }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var auth: AuthViewModel
    private(set) var spotlight: SpotlightViewModel
    private(set) var approvals: ApprovalsViewModel
    private(set) var approvalsTree: ApprovalsTreeViewModel
    private(set) var financePersonal: FinancePersonalViewModel
    private(set) var financeAccounts: FinanceAccountsViewModel
    private(set) var financeTransactions: FinanceTransactionsViewModel
    private(set) var financeInvestments: FinanceInvestmentsViewModel
    /// LIFE terminal view model. Single instance owned by the app shell
    /// so the iOS tab and any future deep links share scrollback state.
    let life: LifeViewModel

    // M7 — People + Inbox.
    private(set) var people: PeopleViewModel
    private(set) var inbox: InboxListViewModel

    // M8 — Advisors + Octagon + Trading Desk (Trading Desk is mac-only;
    // iOS shows a placeholder until the desk layout earns its phone form).
    private(set) var advisors: AdvisorsListViewModel
    private(set) var octagon: OctagonViewModel

    // M9 — Sequences + Settings.
    private(set) var sequences: SequencesViewModel
    private(set) var settings: SettingsViewModel

    // M10 — deep-link router + restoration.
    let lifecycle: AppLifecycleService

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
        let approvalsAPI = LiveApprovalsAPI(client: client)
        self.approvals = ApprovalsViewModel(api: approvalsAPI)
        self.approvalsTree = ApprovalsTreeViewModel(api: approvalsAPI)
        let financeAPI = LiveFinanceAPI(client: client)
        self.financePersonal = FinancePersonalViewModel(api: financeAPI)
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)
        self.life = LifeViewModel(api: LiveLifeAPI(client: client, serverContractLive: false))

        // M7 wiring.
        self.people = PeopleViewModel(api: LivePeopleAPI(client: client))
        self.inbox = InboxListViewModel(api: LiveInboxAPI(client: client))

        // M8 wiring.
        self.advisors = AdvisorsListViewModel(api: LiveAdvisorsAPI(client: client))
        self.octagon = OctagonViewModel(api: LiveOctagonAPI(
            client: client, membershipsContractLive: false
        ))

        // M9 wiring.
        self.sequences = SequencesViewModel(api: LiveSequencesAPI(client: client))
        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())

        // M10 — lifecycle service.
        self.lifecycle = AppLifecycleService()
    }

    func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await auth.restoreFromStore()
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

private struct RootShell: View {
    @Bindable var appModel: AppModel

    var body: some View {
        switch appModel.auth.state {
        case .signedIn:
            RootTabView(appModel: appModel)
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

/// Five visible tabs (HIG cap). Anything that doesn't earn a top-level
/// tab lives in the `More` tab as a NavigationStack list.
private struct RootTabView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        TabView {
            SpotlightView(viewModel: appModel.spotlight)
                .identity(.editorial)
                .tabItem { Label("Spotlight", systemImage: "sparkles") }

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

            ApprovalsTab(flat: appModel.approvals, tree: appModel.approvalsTree)
                .identity(.editorial)
                .tabItem { Label("Approvals", systemImage: "checkmark.seal") }

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

/// Flat vs Tree is a top-of-screen segmented control. Both bind to the
/// shared view models on `AppModel` so switching back and forth doesn't
/// re-fetch or lose expansion / selection state.
private struct ApprovalsTab: View {
    let flat: ApprovalsViewModel
    let tree: ApprovalsTreeViewModel

    private enum Surface: Hashable { case flat, tree }
    @State private var surface: Surface = .flat

    var body: some View {
        VStack(spacing: 0) {
            Picker("Approvals surface", selection: $surface) {
                Text("Flat").tag(Surface.flat)
                Text("Tree").tag(Surface.tree)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            switch surface {
            case .flat: ApprovalsFlatView(viewModel: flat)
            case .tree: ApprovalsTreeView(viewModel: tree)
            }
        }
    }
}

/// "More" tab. Hosts the six surfaces that did not earn a top-level tab:
/// People, Inbox, Advisors, Octagon, Sequences, Settings. Trading Desk
/// renders its iOS placeholder; the real desk is mac-only.
private struct MoreTab: View {
    let appModel: AppModel

    private enum Route: Hashable {
        case people, inbox, advisors, octagon
        case tradingDesk, sequences, settings
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Workspace") {
                    NavigationLink(value: Route.people) {
                        Label("People", systemImage: "person.2")
                    }
                    NavigationLink(value: Route.inbox) {
                        Label("Inbox", systemImage: "tray")
                    }
                }
                Section("Intelligence") {
                    NavigationLink(value: Route.advisors) {
                        Label("Advisors", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink(value: Route.octagon) {
                        Label("Octagon", systemImage: "octagon")
                    }
                }
                Section("Investing") {
                    NavigationLink(value: Route.tradingDesk) {
                        Label("Trading Desk", systemImage: "chart.bar.doc.horizontal")
                    }
                }
                Section("Outreach") {
                    NavigationLink(value: Route.sequences) {
                        Label("Sequences", systemImage: "paperplane")
                    }
                }
                Section {
                    NavigationLink(value: Route.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .people:
                    PeopleView(viewModel: appModel.people)
                        .identity(.editorial)
                case .inbox:
                    InboxListView(viewModel: appModel.inbox)
                        .identity(.editorial)
                case .advisors:
                    AdvisorsView(viewModel: appModel.advisors)
                        .identity(.cockpitInstrument)
                case .octagon:
                    OctagonView(viewModel: appModel.octagon)
                        .identity(.cockpitInstrument)
                case .tradingDesk:
                    TradingDeskPlaceholderView()
                        .identity(.cockpitInstrument)
                case .sequences:
                    SequencesView(viewModel: appModel.sequences)
                        .identity(.editorial)
                case .settings:
                    SettingsForm(settings: appModel.settings, auth: appModel.auth)
                        .identity(.editorial)
                }
            }
        }
    }
}
