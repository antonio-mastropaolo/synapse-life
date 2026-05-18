import SwiftUI
import DesignSystem

/// Single membership list cell.
///
/// Layout: 36pt logo on the left, merchant + relative last-charged
/// date stacked in the middle (with the status pill inline), monthly
/// cost on the right. The whole row is a button so the parent surface
/// can route to the detail explosion view on tap.
@MainActor
struct MembershipRow: View {
    let membership: Membership
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var hover = false

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        Button(action: action) {
            HStack(spacing: 14) {
                MerchantLogoView(
                    merchant: membership.merchant,
                    fallbackColor: MembershipStatusPill.tone(for: membership.status),
                    size: 36
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(membership.merchant)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                            .lineLimit(1)
                        MembershipStatusPill(status: membership.status)
                    }
                    Text(lastChargedDescription)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatCurrency(membership.monthlyCost))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .monospacedDigit()
                    Text("/MO")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBackground(tokens: tokens))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(rowBorder(tokens: tokens), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityIdentifier("memberships.row.\(membership.merchant.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    private func rowBackground(tokens: TokenSet) -> Color {
        if isSelected { return tokens.foregroundPrimary.color.opacity(0.07) }
        if hover { return tokens.foregroundPrimary.color.opacity(0.04) }
        return tokens.foregroundPrimary.color.opacity(0.025)
    }

    private func rowBorder(tokens: TokenSet) -> Color {
        if isSelected { return tokens.foregroundPrimary.color.opacity(0.18) }
        return tokens.foregroundPrimary.color.opacity(0.06)
    }

    /// "Charged 4 days ago" / "Charged today" — picks the right
    /// relative-date phrase so the row reads conversationally.
    private var lastChargedDescription: String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: membership.lastChargedAt,
            to: Date()
        ).day ?? 0
        switch days {
        case 0:    return "Charged today"
        case 1:    return "Charged yesterday"
        case 2...60:
            return "Charged \(days) days ago"
        default:
            let df = DateFormatter()
            df.dateFormat = "MMM d, yyyy"
            return "Last charge \(df.string(from: membership.lastChargedAt))"
        }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}
