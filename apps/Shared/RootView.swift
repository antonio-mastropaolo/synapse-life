import SwiftUI
import DesignSystem

/// Shared cross-platform shell entry point.
///
/// The shell is Cockpit Dense — SF Mono at the 11pt base, ledger-stripe
/// rows, signed gain/loss deltas, and a tree-style sidebar. We host the
/// rendering inside `DesignSystem.CockpitShellPreview` so the SnapshotTests
/// target (which does not depend on apps/*) can lock the same chrome.
///
/// Per-surface identities still apply inside their windows (LIFE uses
/// `.identity(.terminalAmber)`, Spotlight / Approvals / People / Inbox
/// use `.identity(.editorial)`). The shell is what an unidentified
/// subtree inherits.
@MainActor
public struct RootView: View {

    public init() {}

    public var body: some View {
        CockpitShellPreview()
    }
}
