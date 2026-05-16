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
    private(set) var approvals: ApprovalsViewModel
    private(set) var approvalsTree: ApprovalsTreeViewModel
    private(set) var financePersonal: FinancePersonalViewModel
    private(set) var financeAccounts: FinanceAccountsViewModel
    private(set) var financeTransactions: FinanceTransactionsViewModel
    private(set) var financeInvestments: FinanceInvestmentsViewModel
    /// LIFE terminal view model. Single instance owned by the app shell
    /// so the iOS tab and any future deep links share scrollback state.
    let life: LifeViewModel
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
            RootTabView(
                spotlight: appModel.spotlight,
                approvals: appModel.approvals,
                approvalsTree: appModel.approvalsTree,
                financePersonal: appModel.financePersonal,
                financeAccounts: appModel.financeAccounts,
                financeTransactions: appModel.financeTransactions,
                financeInvestments: appModel.financeInvestments,
                life: appModel.life,
                auth: appModel.auth
            )
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
    let approvals: ApprovalsViewModel
    let approvalsTree: ApprovalsTreeViewModel
    let financePersonal: FinancePersonalViewModel
    let financeAccounts: FinanceAccountsViewModel
    let financeTransactions: FinanceTransactionsViewModel
    let financeInvestments: FinanceInvestmentsViewModel
    let life: LifeViewModel
    let auth: AuthViewModel

    var body: some View {
        TabView {
            SpotlightView(viewModel: spotlight)
                .identity(.editorial)
                .tabItem { Label("Spotlight", systemImage: "sparkles") }

            FinanceTab(
                personal: financePersonal,
                accounts: financeAccounts,
                transactions: financeTransactions,
                investments: financeInvestments
            )
            .identity(.cockpitInstrument)
            .tabItem { Label("Finance", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack {
                LifeTerminalView(viewModel: life)
                    .navigationTitle("Life")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .identity(.terminalAmber)
            .tabItem { Label("Life", systemImage: "terminal") }

            ApprovalsTab(flat: approvals, tree: approvalsTree)
                .identity(.editorial)
                .tabItem { Label("Approvals", systemImage: "checkmark.seal") }

            MoreTab(auth: auth)
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
    }
}

/// iOS Finance tab: NavigationStack rooted at the Personal screen, with
/// pushed navigation to Accounts / Transactions / Investments. Trading
/// Desk (`/finance/work`) is deferred to M8.
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
