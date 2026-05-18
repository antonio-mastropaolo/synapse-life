import Foundation
import SwiftUI

/// Top-level sidebar route for the macOS shell.
///
/// The Copilot redesign expanded the sidebar from three first-class
/// destinations (Finance / Life / Advisors) to eleven, matching the
/// Copilot reference shell. The new top-level rows are flat — no
/// disclosure groups, no parent/child semantics — because the
/// reference treats them as peers under a single visual section.
///
/// The legacy `.finance(FinanceSurface)` case is preserved for the
/// in-flight live shell (`CopilotShellMac` routes the redesigned
/// `.transactions` / `.accounts` / `.investments` top-level rows
/// through the existing FinancePersonalView family by mapping each
/// row to its `.finance(_)` peer). Removing the case would break
/// [[RootShellSelectionTests]] and the live FinanceSurface router.
public enum RootDestination: Sendable, Equatable, Hashable {

    // MARK: - New Copilot rows
    case dashboard
    case transactions
    case goals
    case cashFlow
    case accounts
    case investments
    case categories
    case recurrings
    case memberships

    // MARK: - Surviving Synapse-only rows
    case life
    case advisors

    // MARK: - INTELLIGENCE section (AI++ wedge, 2026-05-17)
    //
    // Added during the four-branch Copilot integration. Each surface
    // owns a feature module under `Sources/Features/{Digest,Forecast,
    // SmartAlerts}/`; the macOS shell renders them in a dedicated
    // INTELLIGENCE section below MY ACCOUNTS. `.ask` and
    // `.anomalyExplainer` are present so a deep link or sheet trigger
    // can drive routing, but they are intentionally NOT in the
    // `canonicalOrder` because they present as sheets, not sidebar
    // rows. See `intelligenceOrder` below for the sidebar set.
    case digest
    case forecast
    case smartAlerts
    case ask
    case anomalyExplainer

    // MARK: - Legacy finance sub-routes
    //
    // Kept for back-compat with the surviving FinancePersonalView /
    // FinanceAccountsView / FinanceTransactionsView / FinanceInvestmentsView
    // family. The Copilot redesign routes the new top-level rows through
    // these surfaces under the hood.
    case finance(FinanceSurface)

    // MARK: - Parameterized leaf — MY ACCOUNTS drill-down
    //
    // Reached from a MY ACCOUNTS sidebar row tap. Deliberately omitted
    // from `canonicalOrder` for the same reason `.ask` and
    // `.anomalyExplainer` are: it's parameterized and never rendered as
    // a sidebar row of its own — the account rows themselves are the
    // entry point, and the detail pane swaps content based on the id.
    //
    // The detail pane resolves the id against
    // `FinanceAccountsViewModel.accounts` and renders an in-depth view
    // (balance chart, KPI cluster, scoped recent transactions, scoped
    // recurrings). On a miss, the pane paints an "Account not found"
    // empty state — no crash, no fabricated data. See
    // [[AccountDetailView]] for the surface.
    case accountDetail(id: String)
}

extension RootDestination {
    /// Canonical order in which the macOS sidebar paints its rows.
    /// Other agents render content for these destinations and key off
    /// this ordering — changing it is a breaking change.
    ///
    /// Updated 2026-05-17 (Copilot integration): the original eleven
    /// rows survive in their order, followed by the three INTELLIGENCE
    /// rows from the AI++ wedge. `.ask` and `.anomalyExplainer` are
    /// deliberately omitted because they present as sheets, not
    /// sidebar rows — see `intelligenceOrder` for the sheet-routable
    /// destinations.
    public static let canonicalOrder: [RootDestination] = [
        .dashboard,
        .transactions,
        .goals,
        .cashFlow,
        .accounts,
        .investments,
        .categories,
        .recurrings,
        .memberships,
        .life,
        .advisors,
        .digest,
        .forecast,
        .smartAlerts
    ]

    /// The INTELLIGENCE-section sidebar rows, in painting order. The
    /// macOS sidebar renders this list under a "INTELLIGENCE" header
    /// below MY ACCOUNTS. Kept distinct from `canonicalOrder` so a
    /// caller iterating intelligence-only surfaces (e.g. an Apple
    /// Intelligence settings pane) does not have to filter the full
    /// list manually.
    public static let intelligenceOrder: [RootDestination] = [
        .digest,
        .forecast,
        .smartAlerts
    ]
}

/// Sub-routes for the Finance destination. Mirrors the four surviving
/// finance screens — Personal is the showcase, Accounts/Transactions/
/// Investments are the other three of the cluster.
public enum FinanceSurface: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case personal
    case accounts
    case transactions
    case investments

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .personal:     return "Personal"
        case .accounts:     return "Accounts"
        case .transactions: return "Transactions"
        case .investments:  return "Investments"
        }
    }

    public var systemImage: String {
        switch self {
        case .personal:     return "house"
        case .accounts:     return "list.bullet.rectangle"
        case .transactions: return "arrow.left.arrow.right"
        case .investments:  return "chart.pie"
        }
    }
}

/// Pure selection state for the macOS Cockpit shell. UI-free so it can be
/// exercised in tests without rendering. SwiftUI views observe it via
/// `@Bindable` and read the current destination to switch the detail pane.
///
/// The class is `@Observable` and `@MainActor`-isolated because the only
/// readers are SwiftUI views on the main actor.
@MainActor
@Observable
public final class RootShellViewModel {

    /// The destination currently surfaced in the detail pane. Setting this
    /// is what a sidebar tap does. Persists across the lifetime of the
    /// shell; window restoration carries it through `SceneStorage` at the
    /// view layer.
    public var selection: RootDestination

    /// Optional id of a MY ACCOUNTS row the user just tapped. Cleared on
    /// any top-level destination change. Agent 2 will read this from the
    /// Transactions VM to scope the list to that account; until that wire
    /// lands, the slot is informational.
    public var selectedAccountId: String?

    public init(selection: RootDestination = .dashboard) {
        self.selection = selection
        self.selectedAccountId = nil
    }

    /// Convenience used by the sidebar rows. A top-level row tap routes
    /// straight to its destination and clears any pinned account — the
    /// sidebar carries one selection at a time.
    public func select(_ destination: RootDestination) {
        selection = destination
        selectedAccountId = nil
    }

    /// Records that the operator clicked a MY ACCOUNTS row. The
    /// destination is not touched here — preserved from the original
    /// Copilot integration where the slot was informational only.
    ///
    /// New code should call [[select(accountDetail:)]] instead: that
    /// path sets BOTH the destination and the account id atomically,
    /// so the detail pane actually swaps to `AccountDetailView`.
    /// `select(account:)` is kept because [[SidebarSelectionTests]]
    /// (`accountTapRecordsId`, `topLevelTapClearsAccount`) locks the
    /// "id-only" contract and removing it would break the suite.
    public func select(account id: String) {
        selectedAccountId = id
    }

    /// Drives the MY ACCOUNTS drill-down. Sets BOTH the selection
    /// (`.accountDetail(id:)`) AND the `selectedAccountId` slot so the
    /// sidebar row paints its active accent while the detail pane
    /// swaps to `AccountDetailView`. Top-level row taps subsequently
    /// clear `selectedAccountId` via [[select(_:)]], same as before.
    public func select(accountDetail id: String) {
        selection = .accountDetail(id: id)
        selectedAccountId = id
    }

    /// Whether the given destination is the current selection. Used by
    /// the sidebar to paint the active-row accent bar. Top-level rows
    /// match exactly; the legacy `.finance(_)` shape preserves its
    /// "parent FINANCE row activates for every leaf" semantic.
    public func isActive(_ destination: RootDestination) -> Bool {
        switch (destination, selection) {
        case (.finance, .finance):
            // Parent FINANCE row is active whenever any finance leaf is
            // selected — encoded as `destination == .finance(.personal)`
            // because the parent has no surface of its own.
            return true
        default:
            return destination == selection
        }
    }

    /// Whether a specific finance sub-route is the current selection. The
    /// child rows use this so only the *exact* match paints the accent.
    public func isActiveFinanceSurface(_ surface: FinanceSurface) -> Bool {
        if case .finance(let s) = selection { return s == surface }
        return false
    }
}
