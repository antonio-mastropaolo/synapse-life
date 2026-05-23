import SwiftUI
import DesignSystem

/// Dense AI summary card surfaced at the top of the Memberships tab.
///
/// Displays:
///   * "$X/mo recoverable across N actions" headline.
///   * Top 3 tips, each one merchant + rationale + savings figure.
///
/// Hidden by the parent when `summary.totalPotentialSavingsMonthly`
/// rounds to zero — there's no point in showing a "$0.00 recoverable"
/// card when the user has nothing to recover.
@MainActor
struct MembershipsOptimizationCard: View {
    let summary: OptimizationSummary
    let memberships: [Membership]
    let onSelect: (Membership) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let accent = Color(red: 0.27, green: 0.83, blue: 0.89)
        VStack(alignment: .leading, spacing: 12) {
            header(tokens: tokens, accent: accent)
            if !summary.topTips.isEmpty {
                Divider().overlay(tokens.foregroundPrimary.color.opacity(0.08))
                VStack(spacing: 6) {
                    ForEach(summary.topTips) { tip in
                        tipRow(tip: tip, tokens: tokens)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DS.Surface.card,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(accent.opacity(0.30), lineWidth: 1)
        )
        .elevation(DS.Elevation.card)
        .accessibilityIdentifier("memberships.optimization.card")
    }

    @ViewBuilder
    private func header(tokens: TokenSet, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI OPTIMIZATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(formatCurrency(summary.totalPotentialSavingsMonthly))/mo")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .monospacedDigit()
                    Text("recoverable across \(summary.actionableTipCount) \(summary.actionableTipCount == 1 ? "action" : "actions")")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func tipRow(tip: OptimizationTip, tokens: TokenSet) -> some View {
        Button {
            if let m = memberships.first(where: { $0.id == tip.merchantId }) {
                onSelect(m)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tip.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.69, blue: 0.22))
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.kind.displayLabel.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text(tip.rationale)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text("\(formatCurrency(tip.estimatedSavingsMonthly))/mo")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.34, green: 0.78, blue: 0.50))
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("memberships.optimization.tip.\(tip.id)")
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
