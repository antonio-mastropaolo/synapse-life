import SwiftUI
import DesignSystem
import Models

/// Colored capsule that names a transaction category. Matches the
/// Copilot screenshot — uppercased monospace label, bold weight,
/// white text on a category-coloured fill.
///
/// Kept as its own view so the dashboard row can compose it without
/// owning the palette resolution; both the inline row treatment and
/// the inspector's "category mix" chart can reuse it.
@MainActor
struct DashboardCategoryPill: View {

    let category: TransactionCategory

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        Text(DashboardCategoryPalette.label(for: category))
            // 9pt bold matches the Copilot pill — slightly under the
            // ledger row body so it reads as metadata, not content.
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(
                DashboardCategoryPalette.foreground(for: category, tokens: tokens)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(DashboardCategoryPalette.fill(for: category, tokens: tokens))
            )
            .accessibilityLabel("Category: \(category.displayLabel)")
    }
}
