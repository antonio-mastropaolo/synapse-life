import SwiftUI
import DesignSystem

/// Conditional banner painted above the membership list whenever the
/// optimiser found one-or-more `DuplicateCluster`s. Each cluster
/// renders as a row of its own (Streaming / Music / AI tools) — the
/// banner stacks them vertically so the user can see every overlap
/// at a glance.
///
/// Expanding a cluster reveals the matched members so the user can
/// pick which one to drop. The banner doesn't try to recommend a
/// winner — the optimisation tip on the row does that.
@MainActor
struct DuplicatesBanner: View {
    let clusters: [DuplicateCluster]
    let onSelect: (Membership) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var expandedCluster: String?

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(clusters) { cluster in
                clusterRow(cluster, tokens: tokens)
            }
        }
    }

    @ViewBuilder
    private func clusterRow(_ cluster: DuplicateCluster, tokens: TokenSet) -> some View {
        let tone = Color(red: 1.00, green: 0.69, blue: 0.22)
        let isExpanded = expandedCluster == cluster.id
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedCluster = isExpanded ? nil : cluster.id
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tone)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline(for: cluster))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                        Text(subline(for: cluster))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(cluster.memberships) { m in
                        Button {
                            onSelect(m)
                        } label: {
                            HStack(spacing: 12) {
                                MerchantLogoView(
                                    merchant: m.merchant,
                                    fallbackColor: MembershipStatusPill.tone(for: m.status),
                                    size: 24
                                )
                                Text(m.merchant)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(tokens.foregroundPrimary.color)
                                Spacer()
                                Text("\(formatCurrency(m.monthlyCost))/mo")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(tokens.foregroundSecondary.color)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(tokens.foregroundPrimary.color.opacity(0.02))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tone.opacity(0.30), lineWidth: 1)
        )
        .accessibilityIdentifier("memberships.duplicateCluster.\(cluster.id)")
    }

    private func headline(for cluster: DuplicateCluster) -> String {
        "\(cluster.memberships.count) \(cluster.categoryLabel.lowercased()) services overlapping"
    }

    private func subline(for cluster: DuplicateCluster) -> String {
        let total = cluster.memberships.reduce(Decimal.zero) { $0 + $1.monthlyCost }
        return "\(formatCurrency(total))/mo combined — pick one to save up to \(formatCurrency(cluster.estimatedSavingsMonthly))/mo"
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
