import SwiftUI
import DesignSystem
import Models

/// One inbox row: checkbox + merchant column + category pill + amount.
///
/// The row is platform-aware: on macOS we use `.toggleStyle(.checkbox)`
/// which renders a true AppKit checkbox; on iOS we draw a custom
/// circle-with-checkmark so the row stays tappable with a 44pt
/// hit target (the system `Toggle` on iOS is a switch by default and
/// doesn't fit Copilot's row affordance).
@MainActor
struct DashboardRowView: View {

    let entry: DashboardEntry

    @Binding var isSelected: Bool

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(alignment: .center, spacing: 12) {
            checkbox
                .frame(width: 22, alignment: .leading)

            merchantColumn(tokens: tokens)

            Spacer(minLength: 8)

            // Canonical pill from the Categories module. Resolves the
            // server category string → `CategoryID` via the shared
            // `CategoryResolver`, then paints with `CategoryID.displayColor`
            // — the source of truth across Dashboard, Categories, and the
            // Copilot chrome. Reconciled 2026-05-17 during the four-branch
            // integration to retire the local `DashboardCategoryPill`.
            CategoryPill(transaction: entry.transaction, size: .compact)

            amountText(tokens: tokens)
                // Tabular monospaced figures so the right edge of
                // every row's amount lines up regardless of digit count.
                .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // Tapping anywhere on the row (not just the checkbox) toggles
        // selection — matches Copilot's row-as-target affordance and
        // is the natural ergonomic on a touch device.
        .onTapGesture {
            isSelected.toggle()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Subviews

    @ViewBuilder
    private var checkbox: some View {
        #if os(macOS)
        Toggle("", isOn: $isSelected)
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.small)
        #else
        // iOS: custom circular checkbox. 22pt is the smallest size
        // that still hits Apple's 44pt minimum when combined with
        // the row's vertical padding.
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(
                isSelected
                ? Color.accentColor
                : Color.secondary.opacity(0.6)
            )
        #endif
    }

    @ViewBuilder
    private func merchantColumn(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(merchantName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                if entry.transaction.pending {
                    Text("PENDING")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(tokens.foregroundSecondary.color.opacity(0.45), lineWidth: 0.5)
                        )
                }
            }
            if let subtitle = subtitleText {
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private func amountText(tokens: TokenSet) -> some View {
        let amount = entry.transaction.amount ?? 0
        let isIncome = amount > 0
        let color: Color = isIncome
            ? tokens.gainAccent.color
            : tokens.foregroundPrimary.color
        Text(formattedAmount(amount))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .accessibilityLabel(
                isIncome
                ? "income \(formattedAmount(amount))"
                : "expense \(formattedAmount(amount))"
            )
    }

    // MARK: - Helpers

    private var merchantName: String {
        entry.transaction.merchantName ?? entry.transaction.name
    }

    private var subtitleText: String? {
        if let description = entry.description, !description.isEmpty {
            return description
        }
        // Fall back to the account name so a row without an explicit
        // description still says something useful.
        return entry.transaction.accountName
    }

    /// Signed currency string with a leading "+" on income and a
    /// leading "-" on expenses. We deliberately do not use
    /// `NumberFormatter`'s `.currency` style because it emits
    /// parentheses for negatives on some locales; the dashboard
    /// follows Copilot's convention of a real minus sign so it
    /// reads identically across locales.
    private func formattedAmount(_ amount: Decimal) -> String {
        let absolute = amount.magnitude
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = entry.transaction.currency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        let body = nf.string(from: absolute as NSDecimalNumber) ?? "$0.00"
        return amount < 0 ? "-\(body)" : "+\(body)"
    }

    private var accessibilityLabel: String {
        let amount = entry.transaction.amount ?? 0
        return "\(merchantName), \(DashboardCategoryPalette.label(for: entry.transaction.category)), \(formattedAmount(amount))"
    }
}
