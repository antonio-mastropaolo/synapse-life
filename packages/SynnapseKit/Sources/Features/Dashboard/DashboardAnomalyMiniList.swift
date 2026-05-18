import SwiftUI
import DesignSystem
import Models

/// Inspector card: up to three flagged anomalies. Each row paints a
/// caret triangle, the merchant name, and the amount; tapping the
/// row routes through `openAnomalyExplainer(id)` so the integrator
/// can present the full `AnomalyExplainerView`.
///
/// The card collapses entirely when `anomalies` is empty — there's
/// no value in showing an empty-state stub for this surface.
@MainActor
struct DashboardAnomalyMiniList: View {

    let anomalies: [DashboardEntry]

    /// Tap target. Receives the `DashboardEntry.id` so the integrator
    /// can resolve the underlying transaction without re-walking the
    /// list.
    var openAnomalyExplainer: ((String) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        if anomalies.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("FLAGGED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(tokens.foregroundSecondary.color)

                ForEach(anomalies.prefix(3)) { entry in
                    Button { openAnomalyExplainer?(entry.id) } label: {
                        row(entry: entry, tokens: tokens)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tokens.surface.color)
            )
        }
    }

    @ViewBuilder
    private func row(entry: DashboardEntry, tokens: TokenSet) -> some View {
        let amount = entry.transaction.amount ?? 0
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.lossAccent.color)
            Text(merchantName(entry))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(formatAmount(amount, currency: entry.transaction.currency))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Flagged: \(merchantName(entry)), \(formatAmount(amount, currency: entry.transaction.currency))"
        )
    }

    private func merchantName(_ entry: DashboardEntry) -> String {
        entry.transaction.merchantName ?? entry.transaction.name
    }

    private func formatAmount(_ amount: Decimal, currency: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = currency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        let body = nf.string(from: amount.magnitude as NSDecimalNumber) ?? "$0.00"
        return amount < 0 ? "-\(body)" : "+\(body)"
    }
}
