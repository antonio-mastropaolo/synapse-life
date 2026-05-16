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
            }
        }

        Settings {
            SettingsView(auth: appModel.auth)
                .frame(width: 420, height: 280)
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

private struct SettingsView: View {
    let auth: AuthViewModel

    var body: some View {
        Form {
            Section("Account") {
                switch auth.state {
                case .signedIn(let session):
                    LabeledContent("User", value: session.userId)
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                case .signedOut, .error:
                    Text("Not signed in.")
                        .foregroundStyle(.secondary)
                case .signingIn:
                    ProgressView()
                }
            }
        }
        .padding()
    }
}
