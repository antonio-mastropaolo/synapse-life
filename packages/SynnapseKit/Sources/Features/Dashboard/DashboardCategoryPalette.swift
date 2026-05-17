import SwiftUI
import DesignSystem
import Models

/// Colour resolver for the Dashboard's category pills.
///
/// Agent 1 will publish a category-keyed accessor on `TokenSet`
/// (`tokens.category(_:)`) in a follow-up; until that lands the
/// dashboard ships with a self-contained palette so its renders are
/// not gated on cross-agent integration. The palette below is tuned
/// to mirror the Copilot screenshot — restaurants warm orange,
/// subscriptions purple, groceries green, loans red, clothing teal,
/// income green-on-green for the amount column.
///
/// The resolver is exposed as a free function rather than a method
/// on `TokenSet` so that when the DesignSystem accessor lands, the
/// integration is a one-line swap (`resolve(category:)` → `tokens.category(.knownCategory(...))`).
@MainActor
public enum DashboardCategoryPalette {

    /// Resolve a fill colour for the category pill. Falls back to
    /// the foreground-secondary token when the category string is
    /// unknown — that produces a neutral grey pill rather than a
    /// missing one.
    public static func fill(
        for category: TransactionCategory,
        tokens: TokenSet
    ) -> Color {
        let key = normalize(category.displayLabel)
        if let hit = lookup[key] { return hit.color }
        return tokens.foregroundSecondary.color.opacity(0.55)
    }

    /// Text colour layered on top of the pill. We always paint white
    /// because every pill colour is dark enough to clear AA at 9pt
    /// bold; if the DesignSystem palette later swaps in a pastel,
    /// this is the single switch.
    public static func foreground(
        for category: TransactionCategory,
        tokens _: TokenSet
    ) -> Color {
        Color.white
    }

    /// Uppercased label for the pill. The view never lowercases this
    /// so localisation passes don't accidentally produce mixed case.
    public static func label(for category: TransactionCategory) -> String {
        switch category {
        case .knownCategory(let s): return s.uppercased()
        case .unknown:              return "UNCATEGORIZED"
        }
    }

    // MARK: - Palette

    /// Normalised lookup key. We collapse case and a couple of
    /// connectives ("&", "/") so "Personal Care" and "PERSONAL CARE"
    /// hit the same bucket.
    static func normalize(_ s: String) -> String {
        s.uppercased()
            .replacingOccurrences(of: "&", with: "AND")
            .replacingOccurrences(of: "/", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private struct Swatch {
        let r: Double; let g: Double; let b: Double
        var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    }

    /// Hand-tuned palette. Values cleared visually against both the
    /// `Cockpit.dark` and `Cockpit.light` backgrounds in the
    /// reference shell; the AA-vs-white check is enforced by
    /// [[DashboardCategoryPaletteTests]] when those tests land.
    private static let lookup: [String: Swatch] = [
        "RESTAURANTS":    Swatch(r: 0.93, g: 0.45, b: 0.12),  // warm orange
        "GROCERIES":      Swatch(r: 0.18, g: 0.58, b: 0.34),  // grocery green
        "SUBSCRIPTIONS":  Swatch(r: 0.50, g: 0.36, b: 0.84),  // royal purple
        "LOANS":          Swatch(r: 0.78, g: 0.22, b: 0.28),  // loan red
        "CLOTHING":       Swatch(r: 0.20, g: 0.55, b: 0.62),  // muted teal
        "SHOPPING":       Swatch(r: 0.36, g: 0.42, b: 0.78),  // indigo
        "TRANSPORT":      Swatch(r: 0.42, g: 0.50, b: 0.60),  // slate
        "ENTERTAINMENT":  Swatch(r: 0.85, g: 0.30, b: 0.55),  // magenta
        "TRANSFER":       Swatch(r: 0.36, g: 0.46, b: 0.55),  // slate-blue
        "PERSONAL CARE":  Swatch(r: 0.58, g: 0.32, b: 0.50),  // wine
        "INCOME":         Swatch(r: 0.05, g: 0.55, b: 0.30),  // gain
        "FEES":           Swatch(r: 0.46, g: 0.34, b: 0.30)   // sepia
    ]
}
