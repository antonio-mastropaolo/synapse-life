import SwiftUI
import DesignSystem
import Models

/// Wraps [[DashboardRowView]] with an inline-expanded peek that lists
/// recent same-merchant transactions.
///
/// Tap interaction:
///   - Tap the row body → toggles selection (existing behaviour).
///   - Tap the disclosure chevron on the trailing edge → toggles
///     `expandedRowId` on the view model.
///
/// We deliberately separate the two tap targets so the chevron is a
/// distinct affordance — tapping the body for "select" and the
/// chevron for "expand" mirrors Copilot's row pattern and avoids the
/// ambiguity of a single tap target driving two pieces of state.
@MainActor
struct DashboardExpandableRow: View {

    let entry: DashboardEntry
    @Binding var isSelected: Bool

    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let recentPeers: [DashboardEntry]

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                DashboardRowView(entry: entry, isSelected: $isSelected)
                // Disclosure chevron — separate hit target on the
                // trailing edge. Inset 6pt so it doesn't fight the
                // amount column.
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
            }

            if isExpanded {
                expandedDetail(tokens: tokens)
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.28),
            value: isExpanded
        )
    }

    @ViewBuilder
    private func expandedDetail(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT FROM THIS MERCHANT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(tokens.foregroundSecondary.color)

            if recentPeers.isEmpty {
                Text("No prior charges from this merchant.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            } else {
                ForEach(recentPeers) { peer in
                    HStack {
                        Text(formatDate(peer.transaction.date))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                            .frame(width: 56, alignment: .leading)
                        Spacer()
                        Text(formatAmount(peer.transaction.amount ?? 0,
                                          currency: peer.transaction.currency))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(tokens.foregroundPrimary.color)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.surface.color.opacity(0.4))
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
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
