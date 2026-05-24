import SwiftUI
import SwiftData
import AppKit
import Auth
import Features
import Networking
import Models
import DesignSystem
import AppLifecycle

@main
struct SynapseLifeMacApp: App {

    /// Single construction seam shared with the iOS shell. Owns every VM and
    /// the persistence stores; the scene below is just platform glue.
    @State private var core = AppCore(
        useDemoData: ProcessInfo.processInfo.environment["SYNAPSE_USE_DEMO"] == "1"
    )
    @State private var routing = RootShellViewModel()
    /// Whether the Ask sheet is currently presented. The keystroke
    /// (`⌘K`) and the legacy command-bar entry points both flip this
    /// flag; the sheet itself is rendered as a centered overlay so it
    /// can use the same focus / dim semantics as the previous
    /// `CommandBarView` while delivering the richer
    /// `IntelligenceAskView` answer surface.
    @State private var isAskPresented: Bool = false

    /// Sidebar visibility — bound to the menu-bar "Hide / Show Sidebar"
    /// command (⌃⌘S). Stored in `SceneStorage` so a window restored from
    /// last launch reopens with the same chrome the operator left it.
    @SceneStorage("mac.shell.sidebarVisible") private var sidebarVisible: Bool = true

    /// Persisted top-level sidebar selection. The default is
    /// `.dashboard`; a stored value is replayed into the routing VM
    /// on appear so the next window restoration lands on the surface
    /// the operator was last using. Stored as the destination's
    /// `String` id so SceneStorage's narrow Codable surface accepts it.
    @SceneStorage("mac.shell.selectedSurface") private var storedSelection: String = "dashboard"

    var body: some Scene {
        WindowGroup("Synapse") {
            ZStack(alignment: .top) {
                CopilotShellMac(
                    routing: routing,
                    personal: core.financePersonal,
                    accounts: core.financeAccounts,
                    transactions: core.financeTransactions,
                    investments: core.financeInvestments,
                    activity: core.activity,
                    advisors: core.advisors,
                    dashboard: core.dashboard,
                    categories: core.categories,
                    digest: core.digest,
                    forecast: core.forecast,
                    smartAlerts: core.smartAlerts,
                    subscriptions: core.subscriptions,
                    recurrings: core.recurrings,
                    memberships: core.memberships,
                    goals: core.goals,
                    sidebarVisible: sidebarVisible,
                    showsDemoDataFooter: core.usesDemoData,
                    onProactiveDismiss: { signal in
                        Task { await core.dismissSignal(id: signal.id) }
                    }
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
                        viewModel: core.intelligenceAsk,
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
            .task {
                core.registerBackgroundRefresh()
                await core.bootstrap()
            }
            .onAppear {
                // Replay the persisted top-level destination so a
                // window restored from last launch lands on the same
                // surface. Unknown ids degrade to `.dashboard`.
                routing.select(restoredDestination())
            }
            .onChange(of: routing.selection) { _, newValue in
                storedSelection = sceneStorageId(for: newValue)
            }
            .onOpenURL { url in
                core.lifecycle.handle(url: url)
            }
            // Inject the shared SwiftData container so a future widget /
            // share-extension and any `@Query`-driven descendant read the
            // same store the persistence actors write through.
            .modelContainer(core.modelContainer)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            MacCommands(
                routing: routing,
                isAskPresented: $isAskPresented,
                sidebarVisible: $sidebarVisible,
                auth: core.auth
            )
        }

        Settings {
            SettingsScene(settings: core.settings, auth: core.auth)
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
        core.intelligenceAsk.cancel()
        isAskPresented = false
    }

    // MARK: - Scene-storage routing

    /// Restore a `RootDestination` from the persisted scene-storage id.
    /// Only the well-known top-level sidebar destinations are valid
    /// restoration targets — parameterized leaves (`.accountDetail`,
    /// `.finance(_)`) deliberately fall back to `.dashboard` so a
    /// stale id from a previous build never crashes the window.
    private func restoredDestination() -> RootDestination {
        switch storedSelection {
        case "dashboard":      return .dashboard
        case "transactions":   return .transactions
        case "goals":          return .goals
        case "cashFlow":       return .cashFlow
        case "accounts":       return .accounts
        case "investments":    return .investments
        case "categories":     return .categories
        case "recurrings":     return .recurrings
        case "memberships":    return .memberships
        case "activity":       return .activity
        case "advisors":       return .advisors
        case "digest":         return .digest
        case "forecast":       return .forecast
        case "smartAlerts":    return .smartAlerts
        default:               return .dashboard
        }
    }

    /// Compact id for SceneStorage. Returns `nil`-safe strings for
    /// parameterized destinations so the store value never carries
    /// associated data (SceneStorage is `String`-typed).
    private func sceneStorageId(for destination: RootDestination) -> String {
        switch destination {
        case .dashboard:         return "dashboard"
        case .transactions:      return "transactions"
        case .goals:             return "goals"
        case .cashFlow:          return "cashFlow"
        case .accounts:          return "accounts"
        case .investments:       return "investments"
        case .categories:        return "categories"
        case .recurrings:        return "recurrings"
        case .memberships:       return "memberships"
        case .activity:          return "activity"
        case .advisors:          return "advisors"
        case .digest:            return "digest"
        case .forecast:          return "forecast"
        case .smartAlerts:       return "smartAlerts"
        case .ask:               return "dashboard"
        case .anomalyExplainer:  return "dashboard"
        case .finance:           return "transactions"
        case .accountDetail:     return "accounts"
        }
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
