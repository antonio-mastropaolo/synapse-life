import SwiftUI
import SwiftData
import Auth
import Features
import Networking
import Models
import AppLifecycle

@main
struct SynapseLifeApp: App {
    /// Single construction seam shared with the macOS shell. Owns every VM and
    /// the persistence stores; the scenes below are just platform glue.
    @State private var core = AppCore(
        useDemoData: ProcessInfo.processInfo.environment["SYNAPSE_USE_DEMO"] == "1"
    )

    var body: some Scene {
        WindowGroup {
            // The login gate was removed: the tab view renders
            // unconditionally so the app boots straight into Finance /
            // Life / Advisors. Auth is now a user-initiated action
            // surfaced from Settings (under the More tab), not a
            // startup blocker.
            RootTabView(core: core)
                .task {
                    core.registerBackgroundRefresh()
                    await core.bootstrap()
                }
                .onOpenURL { url in
                    // Deep links route through `AppLifecycleService`.
                    // Unrecognised URLs return nil from `parse(url:)` and
                    // are silently dropped — matches the macOS shell.
                    core.lifecycle.handle(url: url)
                }
                // Inject the shared SwiftData container so descendants and a
                // future widget read the store the persistence actors write.
                .modelContainer(core.modelContainer)
        }
    }
}

// The previous `RootShell` wrapper switched between `RootTabView` and
// `SignInView` based on `core.auth.state`. That wrapper has been
// removed: the iOS app boots straight into `RootTabView`. Auth is now
// a user-initiated action surfaced from Settings (under the More tab).
// `SignInView`, `AuthViewModel`, `SessionStore`, and `LiveSessionAPI`
// stay in the codebase and remain reachable from Settings.

/// Visible tabs (Copilot-inspired reshape):
///   Dashboard · Transactions · Investments · More
///
/// The shape mirrors Copilot's bottom rail. The first tab is the
/// review-queue inbox rather than the finance hub — that matches the
/// product's primary action ("look at what's new and triage") rather
/// than the analytic view ("how much do I have"). Investments is a
/// first-class slot because it's a surface a user opens daily without
/// a triage intent.
///
/// More holds the long tail: Personal, Accounts, Subscriptions,
/// Recurrings, Life, Advisors, Settings, plus the Sign-in entry. The
/// drill-down list lives in [[MoreTab]].
///
/// The Cash-flow surface is not yet a shipping feature, so it has no
/// bottom-rail slot in release builds; the in-progress tab is mounted
/// only under DEBUG so the team can exercise it locally.
///
/// Synapse is a private-life client; work surfaces from synapse-v2
/// (Spotlight, Approvals, People, Inbox, Sequences, Octagon, Trading
/// Desk) deliberately do not live here.
private struct RootTabView: View {
    @Bindable var core: AppCore

    /// The visible tab identifiers. We track selection ourselves
    /// (rather than letting `TabView` drive an implicit `Int`) so the
    /// `onChange` handler can fire a selection haptic the instant the
    /// user lands on a new tab. Apple's own tab bar does not haptic on
    /// switch; we add it because every top-tier finance app on iOS
    /// does, and the absence reads as a missing affordance.
    enum Tab: Hashable {
        case dashboard, transactions, investments, more
        #if DEBUG
        case cashflow
        #endif
    }

    @State private var selection: Tab = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            DashboardTab(
                viewModel: core.dashboard,
                onProactiveTap: { _ in
                    // Cross-tab jump: every proactive signal points at an
                    // underlying transaction (a due bill, a new recurring
                    // charge, an anomalous debit), so the Transactions tab is
                    // the surface that shows its context. Deep-routing to the
                    // Recurrings sub-screen (buried under More) is deferred.
                    selection = .transactions
                },
                onProactiveDismiss: { signal in
                    Task { await core.dismissSignal(id: signal.id) }
                }
            )
            .identity(.cockpitInstrument)
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            .tag(Tab.dashboard)

            TransactionsTab(
                viewModel: core.financeTransactions,
                financeAPI: core.financeAPI
            )
            .identity(.cockpitInstrument)
            .tabItem { Label("Transactions", systemImage: "list.bullet.indent") }
            .tag(Tab.transactions)

            #if DEBUG
            // Cash flow is in-progress: its surface still renders sample
            // figures, so it ships only under DEBUG and is never part of
            // a release build's bottom rail.
            CashFlowTab()
                .identity(.cockpitInstrument)
                .tabItem {
                    Label("Cash flow", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(Tab.cashflow)
            #endif

            InvestmentsTab(viewModel: core.financeInvestments)
                .identity(.cockpitInstrument)
                .tabItem { Label("Investments", systemImage: "briefcase") }
                .tag(Tab.investments)

            MoreTab(core: core)
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
/// reads from a single `DashboardViewModel` owned by `AppCore`;
/// the navigation stack here only carries through to a future
/// `TransactionDetailView` push when an inbox row is tapped (not yet
/// wired — the row's primary affordance is selection, not navigation).
private struct DashboardTab: View {
    @Bindable var viewModel: DashboardViewModel
    /// Tap a proactive row to jump to the Transactions tab (the surface that
    /// holds the underlying charge). Owned by the tab container so it can flip
    /// the `TabView` selection.
    var onProactiveTap: ((ProactiveSignal) -> Void)?
    /// Persisted dismiss for proactive-feed rows.
    var onProactiveDismiss: ((ProactiveSignal) -> Void)?

    var body: some View {
        NavigationStack {
            DashboardView(
                viewModel: viewModel,
                openProactiveSignal: onProactiveTap,
                dismissProactiveSignal: onProactiveDismiss
            )
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

#if DEBUG
/// Cash flow tab — in-progress surface. Its module
/// (`Features/CashFlow/**`) still renders sample figures, so this tab
/// is compiled only into DEBUG builds and never reaches a reviewer or
/// shipping user. When the real Cash Flow VM lands this moves out of
/// the DEBUG gate.
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
#endif

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
