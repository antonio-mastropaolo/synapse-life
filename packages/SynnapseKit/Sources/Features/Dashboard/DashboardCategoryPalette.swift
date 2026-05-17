import SwiftUI
import DesignSystem
import Models

/// Color resolver for Dashboard category surfaces.
///
/// CANONICAL SOURCE OF TRUTH: `CategoryID.displayColor` (and its
/// mirror `TokenSet.category(_:)`). The fill resolution below was
/// originally a self-contained palette; on 2026-05-17 (four-branch
/// Copilot integration) we rebased it to delegate into
/// `CategoryResolver` so all three surfaces share one palette.
///
/// `label(for:)` stays a local concern because the Dashboard row's
/// pill needs an uppercased string that matches the server's literal
/// category text, not the localized `CategoryID.displayName`. The
/// fills, foregrounds, and any color-bearing surface should now read
/// from this delegating shim — there are no hard-coded hex values in
/// this file anymore.
@MainActor
public enum DashboardCategoryPalette {

    /// Resolve a fill color for the category pill. Delegates to
    /// `CategoryID.displayColor` via the shared resolver so the
    /// Dashboard pill paints identically to the Categories surface
    /// and the Transactions ledger pill.
    public static func fill(
        for category: TransactionCategory,
        tokens _: TokenSet
    ) -> Color {
        switch category {
        case .knownCategory(let s):
            // `CategoryResolver.mapServerLabel` handles the slug
            // normalization (case + connectives). Unknown labels fall
            // through to `.other`.
            return (CategoryResolver.mapServerLabel(s) ?? .other).displayColor
        case .unknown:
            return CategoryID.other.displayColor
        }
    }

    /// Text color layered on top of the pill. White is the canonical
    /// foreground for every pill because every fill is dark enough to
    /// clear AA at 9pt bold.
    public static func foreground(
        for _: TransactionCategory,
        tokens _: TokenSet
    ) -> Color {
        Color.white
    }

    /// Uppercased label for the pill. Mirrors the server label
    /// verbatim (uppercased) so the row's pill reads the same as the
    /// underlying transaction's raw category string. Localized
    /// display names live on `CategoryID.displayName` for the
    /// Categories surface; the ledger row keeps the server text.
    public static func label(for category: TransactionCategory) -> String {
        switch category {
        case .knownCategory(let s): return s.uppercased()
        case .unknown:              return "UNCATEGORIZED"
        }
    }
}
