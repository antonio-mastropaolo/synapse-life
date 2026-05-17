import Foundation
import SwiftUI

/// Top-level sidebar route for the macOS shell.
///
/// The shell is intentionally flat: three first-class destinations
/// (Finance, Life, Advisors). Finance is the only one with sub-routes,
/// and those are owned by [[FinanceSurface]] so the sidebar can highlight
/// either the parent FINANCE row or one of its children.
public enum RootDestination: Sendable, Equatable, Hashable {
    case finance(FinanceSurface)
    case life
    case advisors
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

    public init(selection: RootDestination = .finance(.personal)) {
        self.selection = selection
    }

    /// Convenience used by the sidebar rows. A parent row tap (FINANCE,
    /// LIFE, ADVISORS) lands on the parent's default destination — for
    /// FINANCE that is `.personal`. Sub-row taps go straight to the leaf.
    public func select(_ destination: RootDestination) {
        selection = destination
    }

    /// Whether the given destination matches the current selection. Used
    /// by the sidebar to paint the active-row accent bar.
    ///
    /// Sub-routes count as activating their parent: when the user is on
    /// `.finance(.accounts)`, both the FINANCE parent row and the Accounts
    /// child row report `true`. The child wins visually because it is the
    /// deeper of the two highlights.
    public func isActive(_ destination: RootDestination) -> Bool {
        switch (destination, selection) {
        case (.finance, .finance):
            // Parent FINANCE row is active whenever any finance leaf is
            // selected — that is what `destination == .finance(.personal)`
            // here represents (we encode the parent as its default leaf
            // because there is no parent-only state).
            return true
        case (.life, .life), (.advisors, .advisors):
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
