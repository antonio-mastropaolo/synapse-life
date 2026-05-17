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
            RootShell(appModel: appModel)
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
        let financeAPI = LiveFinanceAPI(client: client)
        self.financePersonal = FinancePersonalViewModel(api: financeAPI)
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)
        self.lifeAPI = LiveLifeAPI(client: client, serverContractLive: false)

        self.advisors = AdvisorsListViewModel(api: LiveAdvisorsAPI(client: client))

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

/// Top-level shell: shows `SignInView` as a sheet over `RootView` until the
/// `AuthViewModel` reports a session, then drops the sheet.
private struct RootShell: View {
    @Bindable var appModel: AppModel

    private var isSignedIn: Bool {
        if case .signedIn = appModel.auth.state { return true }
        return false
    }

    private var errorMessage: String? {
        if case .error(let reason) = appModel.auth.state { return reason }
        return nil
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
                    },
                    onTapDebugBypass: debugBypassHandler,
                    errorMessage: errorMessage
                )
                .identity(.editorial)
                .frame(minWidth: 480, minHeight: 360)
                .interactiveDismissDisabled(true)
            }
    }

    /// `#if DEBUG` is evaluated at file scope so the property's *existence*
    /// — not just its value — is gated by build configuration. Release
    /// builds compile a `nil` for this handler; the `SignInView` then
    /// hides the bypass row entirely.
    private var debugBypassHandler: (() -> Void)? {
        #if DEBUG
        return {
            Task { await appModel.auth.signInForDebugBypass() }
        }
        #else
        return nil
        #endif
    }
}
