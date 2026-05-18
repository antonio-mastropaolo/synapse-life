import SwiftUI
import DesignSystem

/// Main Memberships surface. Replaces the temporary placeholder that
/// routed the `.memberships` destination through the legacy
/// `SubscriptionsView`.
///
/// Layout:
///   * Header — title + secondary copy.
///   * Hero summary row — services count · $X/mo · $Y/yr.
///   * `DuplicatesBanner` (only when ≥ 1 cluster exists).
///   * `MembershipsOptimizationCard` (only when there's positive
///     monthly savings to surface).
///   * Filter chips — Active / Trial / At-risk / Low usage / All.
///   * List of `MembershipRow`s sorted by monthlyCost desc.
///
/// Tapping a row pushes a `MembershipDetailView` rendered in-place
/// in the same column (macOS pattern — no nested NavigationStack).
@MainActor
public struct MembershipsView: View {

    @Bindable private var store: MembershipsStore

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var selectedID: String?
    @State private var filter: Filter = .all

    public init(store: MembershipsStore) {
        self.store = store
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        Group {
            if let id = selectedID,
               let m = store.memberships.first(where: { $0.id == id }) {
                MembershipDetailView(membership: m) {
                    selectedID = nil
                }
            } else {
                listSurface(tokens: tokens)
            }
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("memberships.root")
    }

    // MARK: - List surface

    @ViewBuilder
    private func listSurface(tokens: TokenSet) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header(tokens: tokens)
                heroSummary(tokens: tokens)
                if !store.duplicateClusters.isEmpty {
                    DuplicatesBanner(clusters: store.duplicateClusters) { m in
                        selectedID = m.id
                    }
                }
                if let summary = store.optimizationSummary,
                   summary.totalPotentialSavingsMonthly > 0 {
                    MembershipsOptimizationCard(
                        summary: summary,
                        memberships: store.memberships
                    ) { m in
                        selectedID = m.id
                    }
                }
                filterChips(tokens: tokens)
                listOrEmptyState(tokens: tokens)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Memberships")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Detected subscriptions with cancellation walkthroughs, duplicate-service clustering, and AI-flagged savings opportunities.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func heroSummary(tokens: TokenSet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            summaryCell(value: "\(store.memberships.count)",
                        label: "Services",
                        tokens: tokens)
            summaryCell(value: formatCurrency(store.totalMonthly),
                        label: "Per month",
                        tokens: tokens,
                        prominent: true)
            summaryCell(value: formatCurrency(store.totalAnnual),
                        label: "Per year",
                        tokens: tokens)
            Spacer()
        }
    }

    @ViewBuilder
    private func summaryCell(value: String, label: String, tokens: TokenSet, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: prominent ? 30 : 20,
                              weight: .semibold,
                              design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func filterChips(tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.label.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(filter == f
                                         ? tokens.foregroundPrimary.color
                                         : tokens.foregroundSecondary.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(filter == f
                                      ? tokens.foregroundPrimary.color.opacity(0.08)
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(tokens.foregroundSecondary.color.opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("memberships.filter.\(f.label.lowercased())")
            }
        }
    }

    @ViewBuilder
    private func listOrEmptyState(tokens: TokenSet) -> some View {
        let filtered = filteredMemberships()
        if filtered.isEmpty {
            emptyState(tokens: tokens)
        } else {
            VStack(spacing: 6) {
                ForEach(filtered) { m in
                    MembershipRow(
                        membership: m,
                        isSelected: selectedID == m.id
                    ) {
                        selectedID = m.id
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func emptyState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(filter == .all
                 ? "No memberships detected yet"
                 : "No memberships in this view")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(filter == .all
                 ? "As transactions accumulate, recurring subscriptions will appear here with cancellation guidance."
                 : "Try a different filter to see other memberships.")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.03))
        )
    }

    // MARK: - Filtering

    enum Filter: CaseIterable, Hashable {
        case active, trial, atRisk, unused, all

        var label: String {
            switch self {
            case .active: return "Active"
            case .trial:  return "Trial"
            case .atRisk: return "At-risk"
            case .unused: return "Low usage"
            case .all:    return "All"
            }
        }

        var matchingStatus: MembershipStatus? {
            switch self {
            case .active: return .active
            case .trial:  return .trial
            case .atRisk: return .atRisk
            case .unused: return .unused
            case .all:    return nil
            }
        }
    }

    private func filteredMemberships() -> [Membership] {
        let base = store.memberships.sorted { $0.monthlyCost > $1.monthlyCost }
        guard let status = filter.matchingStatus else { return base }
        return base.filter { $0.status == status }
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}
