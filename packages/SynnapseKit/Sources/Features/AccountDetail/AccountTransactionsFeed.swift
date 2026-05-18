import SwiftUI
import Models
import DesignSystem

/// Scoped recent-activity feed for the macOS account-detail surface.
///
/// Renders the per-account transaction slice already projected by
/// `AccountDetailViewModel.scopedTransactions` (capped at 50, newest
/// first). Layout follows the Synapse v2 ledger idiom: an eyebrow
/// strip on top, day groups stacked beneath, each with its own header
/// line and total, and an optional "view full history" footer when
/// the uncapped slice exceeds the cap.
///
/// Row chrome intentionally mirrors `FinanceTransactionsRedesigned`'s
/// `expandedTransactionRow` so the account-scoped feed and the
/// category-scoped feed feel like the same component — same logo
/// size, same typography, same inflow/outflow color treatment.
@MainActor
struct AccountTransactionsFeed: View {

    @Bindable private var viewModel: AccountDetailViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    init(viewModel: AccountDetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let scoped = viewModel.scopedTransactions
        let allCount = viewModel.allScopedTransactions.count

        VStack(alignment: .leading, spacing: 16) {
            header(shown: scoped.count, total: allCount, tokens: tokens)

            if scoped.isEmpty {
                emptyState(tokens: tokens)
            } else {
                dayGroups(scoped: scoped, tokens: tokens)
                if allCount > 50 {
                    footer(remaining: allCount - 50, tokens: tokens)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Header strip

    private func header(shown: Int, total: Int, tokens: TokenSet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            Text("Showing \(shown) of \(total)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    // MARK: - Day groups

    private func dayGroups(scoped: [Models.Transaction], tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groupedByDay(scoped)) { group in
                VStack(alignment: .leading, spacing: 6) {
                    dayHeader(group: group, tokens: tokens)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.transactions) { tx in
                            transactionRow(tx, tokens: tokens)
                            if tx.id != group.transactions.last?.id {
                                Divider()
                                    .background(tokens.foregroundSecondary.color.opacity(0.10))
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayHeader(group: DayGroup, tokens: TokenSet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
            Text(formatSignedTotal(group.total, currency: group.currency))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(
                    group.total > 0
                        ? Color(red: 0.34, green: 0.78, blue: 0.50)
                        : tokens.foregroundSecondary.color
                )
        }
        .padding(.bottom, 2)
        .overlay(
            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.10))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Transaction row
    //
    // Matches FinanceTransactionsRedesigned.expandedTransactionRow:
    // 36pt MerchantLogoView, medium 13pt name, mono 10pt date with
    // optional PENDING chip, mono 13pt amount on the right. Inflows
    // (>0) paint green; outflows paint the primary token color.

    private func transactionRow(_ tx: Models.Transaction, tokens: TokenSet) -> some View {
        let categoryName = displayCategoryName(tx)
        let palette = categoryColor(for: tx.category)
        return HStack(spacing: 14) {
            MerchantLogoView(
                merchant: tx.name,
                fallbackColor: palette,
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(tx.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .lineLimit(1)
                    if !categoryName.isEmpty {
                        categoryPill(label: categoryName, color: palette)
                    }
                }
                HStack(spacing: 6) {
                    Text(Self.shortDate.string(from: tx.date))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    if tx.pending {
                        Text("PENDING")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(Color.orange.opacity(0.85))
                    }
                }
            }
            Spacer()
            Text((tx.amount ?? 0).formatted(.currency(code: tx.currency)))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(
                    (tx.amount ?? 0) > 0
                        ? Color(red: 0.34, green: 0.78, blue: 0.50)
                        : tokens.foregroundPrimary.color
                )
        }
        .padding(.vertical, 10)
    }

    private func categoryPill(label: String, color: Color) -> some View {
        Text(label.uppercased())
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(color.opacity(0.30), lineWidth: 0.5)
            )
    }

    // MARK: - Empty state

    private func emptyState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No charges on this account yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Charges will appear here as the ledger refreshes.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private func footer(remaining: Int, tokens: TokenSet) -> some View {
        Button {
            // Wired to a route push by A2 when the full-history view
            // lands. No-op here so the integration seam is explicit.
        } label: {
            HStack(spacing: 6) {
                Text("+\(remaining) more in full history")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tokens.foregroundSecondary.color)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.transactions.fullHistory")
    }

    // MARK: - Day grouping
    //
    // Bucket transactions by calendar-day startOfDay. The ViewModel
    // hands us newest-first already, so we preserve that order in
    // the group list and inside each group.

    private struct DayGroup: Identifiable {
        let id: Date
        let label: String
        let total: Decimal
        let currency: String
        let transactions: [Models.Transaction]
    }

    private func groupedByDay(_ scoped: [Models.Transaction]) -> [DayGroup] {
        let cal = Calendar.current
        var keys: [Date] = []
        var buckets: [Date: [Models.Transaction]] = [:]
        for tx in scoped {
            let day = cal.startOfDay(for: tx.date)
            if buckets[day] == nil {
                keys.append(day)
                buckets[day] = []
            }
            buckets[day]?.append(tx)
        }
        return keys.map { day in
            let txs = buckets[day] ?? []
            let total = txs.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
            let currency = txs.first?.currency ?? "USD"
            return DayGroup(
                id: day,
                label: dayLabel(day),
                total: total,
                currency: currency,
                transactions: txs
            )
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: viewModel.today)
        if cal.isDate(day, inSameDayAs: today) { return "Today" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
           cal.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        // Within the last 6 days: weekday + short date ("Friday, May 15").
        if let weekAgo = cal.date(byAdding: .day, value: -6, to: today),
           day >= weekAgo {
            return Self.weekdayWithDate.string(from: day)
        }
        return Self.mediumDate.string(from: day)
    }

    private func formatSignedTotal(_ value: Decimal, currency: String) -> String {
        let formatted = value.formatted(.currency(code: currency))
        if value > 0 && !formatted.hasPrefix("+") {
            return "+\(formatted)"
        }
        return formatted
    }

    // MARK: - Category palette
    //
    // Mirrors the canonical mapping used by the other AccountDetail
    // redesigns so the swatch color stays stable across surfaces.
    // The wire-side category is a raw string; we route it through
    // CategoryID.from(slug:) to get a stable id and then key the
    // palette off the slug.

    private func categoryColor(for category: TransactionCategory) -> Color {
        guard case .knownCategory(let raw) = category, !raw.isEmpty else {
            return Color(red: 0.47, green: 0.56, blue: 0.61)
        }
        let id = CategoryID.from(slug: slugify(raw))
        return paletteColor(for: id)
    }

    private func paletteColor(for id: CategoryID) -> Color {
        switch id.slug {
        case "restaurants":   return Color(red: 0.30, green: 0.69, blue: 0.42)
        case "subscriptions": return Color(red: 0.63, green: 0.42, blue: 0.84)
        case "groceries":     return Color(red: 0.49, green: 0.70, blue: 0.26)
        case "loans":         return Color(red: 0.90, green: 0.22, blue: 0.21)
        case "clothing":      return Color(red: 0.93, green: 0.25, blue: 0.48)
        case "income":        return Color(red: 0.15, green: 0.65, blue: 0.60)
        case "transfers":     return Color(red: 0.26, green: 0.65, blue: 0.96)
        case "personal-care": return Color(red: 1.00, green: 0.72, blue: 0.30)
        case "entertainment": return Color(red: 1.00, green: 0.66, blue: 0.15)
        case "fees":          return Color(red: 0.55, green: 0.43, blue: 0.39)
        default:              return Color(red: 0.47, green: 0.56, blue: 0.61)
        }
    }

    private func displayCategoryName(_ tx: Models.Transaction) -> String {
        guard case .knownCategory(let raw) = tx.category, !raw.isEmpty else {
            return ""
        }
        return raw
    }

    /// Maps a raw server category string to the slug shape CategoryID
    /// understands. Lowercases, swaps spaces for dashes, strips any
    /// stray non-alphanumeric chars.
    private func slugify(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var out = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if ch == " " || ch == "-" || ch == "_" || ch == "&" {
                if !out.hasSuffix("-") && !out.isEmpty {
                    out.append("-")
                }
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    // MARK: - Formatters

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    private static let weekdayWithDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}
