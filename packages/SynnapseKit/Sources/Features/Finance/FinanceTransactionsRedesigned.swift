import SwiftUI
import Models
import DesignSystem

/// Rich, category-first redesign of the Transactions surface.
///
/// Three visual layers stack vertically:
///
/// 1. **Spend Constellation** — a bubble chart: x = day (last 14d),
///    y = category band, bubble size = transaction amount, fill =
///    category color. Gives an "at-a-glance" map of where money went
///    when, before any list is read.
///
/// 2. **Category Grid** — a wall of category cards, sized by relative
///    spend so the biggest categories visually dominate. Each card
///    surfaces total, transaction count, % of total, mini sparkline
///    of daily spend, and the category's swatch color as the ring.
///
/// 3. **Grouped List** — collapsible per-category sections. Section
///    header carries the swatch, name, total, count, and a mini-bar.
///    Tap to expand and see the transactions inside that category.
///
/// All three layers read from the same `[Transaction]` slice the
/// existing `FinanceTransactionsViewModel` already exposes — no new
/// reducer required.
@MainActor
public struct FinanceTransactionsRedesigned: View {

    @Bindable private var viewModel: FinanceTransactionsViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var expandedCategories: Set<String> = []

    public init(viewModel: FinanceTransactionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header(tokens: tokens)
                if !categoryBuckets.isEmpty {
                    constellationCard(tokens: tokens)
                    categoryGrid(tokens: tokens)
                    groupedList(tokens: tokens)
                } else {
                    emptyState(tokens: tokens)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(tokens.background.color)
        .task { if case .idle = viewModel.state { await viewModel.refresh() } }
    }

    // MARK: - Header

    private func header(tokens: TokenSet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transactions")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("\(totalSpend.formatted(.currency(code: "USD"))) across \(filteredRows.count) transactions in the last 14 days, grouped by category.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
        }
    }

    // MARK: - 1. Spend Constellation

    private func constellationCard(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SPEND CONSTELLATION · LAST 14 DAYS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text("\(constellationDays.count) days × \(categoryBuckets.count) categories")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            constellationChart(tokens: tokens)
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

    private func constellationChart(tokens: TokenSet) -> some View {
        let bands = categoryBuckets
        let days = constellationDays
        let cellHeight: CGFloat = 30
        let leftAxisWidth: CGFloat = 110
        return VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                let plotWidth = geo.size.width - leftAxisWidth
                let plotHeight = CGFloat(bands.count) * cellHeight
                let dayWidth = plotWidth / CGFloat(max(days.count, 1))

                ZStack(alignment: .topLeading) {
                    // Horizontal band guides
                    ForEach(Array(bands.enumerated()), id: \.element.name) { idx, band in
                        let y = CGFloat(idx) * cellHeight
                        Rectangle()
                            .fill(band.color.opacity(0.04))
                            .frame(width: plotWidth, height: cellHeight)
                            .offset(x: leftAxisWidth, y: y)
                        // Category label
                        Text(band.name)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(band.color)
                            .frame(width: leftAxisWidth - 8, alignment: .trailing)
                            .offset(x: 0, y: y + cellHeight / 2 - 6)
                    }

                    // Bubbles
                    ForEach(Array(bands.enumerated()), id: \.element.name) { bandIdx, band in
                        ForEach(band.transactions) { tx in
                            let dayIdx = days.firstIndex(of: dayKey(tx.date)) ?? 0
                            let amt = abs((tx.amount as NSDecimalNumber?)?.doubleValue ?? 0)
                            let r = bubbleRadius(amount: amt)
                            let cx = leftAxisWidth + CGFloat(dayIdx) * dayWidth + dayWidth / 2
                            let cy = CGFloat(bandIdx) * cellHeight + cellHeight / 2
                            Circle()
                                .fill(band.color.opacity(0.55))
                                .overlay(
                                    Circle().stroke(band.color, lineWidth: 1)
                                )
                                .frame(width: r * 2, height: r * 2)
                                .offset(x: cx - r, y: cy - r)
                        }
                    }
                }
                .frame(height: plotHeight)
            }
            .frame(height: CGFloat(bands.count) * cellHeight)

            // X-axis day labels
            HStack(spacing: 0) {
                Spacer().frame(width: leftAxisWidth)
                ForEach(days, id: \.self) { day in
                    Text(dayShort(day))
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        }
    }

    private func bubbleRadius(amount: Double) -> CGFloat {
        // Scale so a $5 charge is ~2pt and a $500 charge is ~14pt.
        let scaled = sqrt(max(amount, 1)) * 0.7
        return max(2.5, min(scaled, 14))
    }

    // MARK: - 2. Category Grid

    private func categoryGrid(tokens: TokenSet) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORIES · SIZED BY SPEND")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(categoryBuckets) { bucket in
                    categoryCard(bucket: bucket, tokens: tokens)
                }
            }
        }
    }

    private func categoryCard(bucket: CategoryBucket, tokens: TokenSet) -> some View {
        let pct = totalSpend > 0 ? (bucket.total / totalSpend) * 100 : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(bucket.color)
                    .frame(width: 8, height: 8)
                Text(bucket.name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", NSDecimalNumber(decimal: pct).doubleValue))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(bucket.color)
            }
            Text(bucket.total.formatted(.currency(code: "USD")))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bucket.dailyTotals.enumerated()), id: \.offset) { _, value in
                    let h = max(2, CGFloat(min(value / max(bucket.peakDaily, 1), 1.0)) * 22)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(bucket.color.opacity(0.75))
                        .frame(height: h)
                }
            }
            .frame(height: 22)
            Text("\(bucket.transactions.count) transactions")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(bucket.color.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - 3. Grouped List

    private func groupedList(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BY CATEGORY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(categoryBuckets) { bucket in
                    categorySection(bucket: bucket, tokens: tokens)
                }
            }
        }
    }

    private func categorySection(bucket: CategoryBucket, tokens: TokenSet) -> some View {
        let isExpanded = expandedCategories.contains(bucket.name)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    if isExpanded {
                        expandedCategories.remove(bucket.name)
                    } else {
                        expandedCategories.insert(bucket.name)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(bucket.color).frame(width: 10, height: 10)
                    Text(bucket.name)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("\(bucket.transactions.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(bucket.color.opacity(0.15))
                        )
                    Spacer()
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(bucket.dailyTotals.enumerated()), id: \.offset) { _, value in
                            let h = max(2, CGFloat(min(value / max(bucket.peakDaily, 1), 1.0)) * 14)
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(bucket.color.opacity(0.55))
                                .frame(width: 3, height: h)
                        }
                    }
                    .frame(height: 14)
                    Text(bucket.total.formatted(.currency(code: "USD")))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(bucket.transactions.sorted(by: { $0.date > $1.date })) { tx in
                        transactionRow(tx, bucket: bucket, tokens: tokens)
                        Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func transactionRow(_ tx: Models.Transaction, bucket: CategoryBucket, tokens: TokenSet) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(bucket.color.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(bucket.color.opacity(0.45), lineWidth: 1)
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(tx.name.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(bucket.color)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                Text(Self.shortDate.string(from: tx.date))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            Text((tx.amount ?? 0).formatted(.currency(code: tx.currency)))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle((tx.amount ?? 0) > 0 ? Color(red: 0.34, green: 0.78, blue: 0.50) : tokens.foregroundPrimary.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private func emptyState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No transactions yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Connect an account to start grouping spend by category.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Derived state

    private struct CategoryBucket: Identifiable {
        let name: String
        let color: Color
        let transactions: [Models.Transaction]
        let total: Decimal
        let dailyTotals: [Double]   // 14 buckets ascending
        let peakDaily: Double
        var id: String { name }
    }

    private var filteredRows: [Models.Transaction] {
        // Last 14 days, debits only — we're visualising SPEND.
        let cutoff = Date().addingTimeInterval(-Double(14 * 86_400))
        return viewModel.rows.filter {
            $0.date >= cutoff && (($0.amount ?? 0) < 0)
        }
    }

    private var constellationDays: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            return dayKey(day)
        }
    }

    private func dayKey(_ d: Date) -> String {
        let cal = Calendar.current
        let day = cal.startOfDay(for: d)
        return Self.keyFormatter.string(from: day)
    }

    private func dayShort(_ key: String) -> String {
        guard let d = Self.keyFormatter.date(from: key) else { return "" }
        return Self.shortDay.string(from: d)
    }

    private var totalSpend: Decimal {
        filteredRows.reduce(Decimal.zero) { acc, tx in
            acc + abs(tx.amount ?? 0)
        }
    }

    private var categoryBuckets: [CategoryBucket] {
        // Group by category string, compute totals, sort descending by spend.
        var byCat: [String: [Models.Transaction]] = [:]
        for tx in filteredRows {
            let name: String
            if case .knownCategory(let s) = tx.category, !s.isEmpty {
                name = s
            } else {
                name = "OTHER"
            }
            byCat[name, default: []].append(tx)
        }
        let days = constellationDays
        let cal = Calendar.current

        return byCat.map { (name, txs) -> CategoryBucket in
            let total = txs.reduce(Decimal.zero) { $0 + abs($1.amount ?? 0) }
            var daily: [Double] = Array(repeating: 0, count: days.count)
            for tx in txs {
                let key = Self.keyFormatter.string(from: cal.startOfDay(for: tx.date))
                if let idx = days.firstIndex(of: key) {
                    daily[idx] += abs((tx.amount as NSDecimalNumber?)?.doubleValue ?? 0)
                }
            }
            let peak = daily.max() ?? 1
            return CategoryBucket(
                name: name,
                color: Self.color(for: name),
                transactions: txs,
                total: total,
                dailyTotals: daily,
                peakDaily: peak
            )
        }
        .sorted { $0.total > $1.total }
    }

    /// Map a category string to a swatch color. Mirrors
    /// `CategoryID.displayColor` for the 11 canonical buckets; falls
    /// back to a deterministic-by-name hash color so unknown labels
    /// still get a stable palette slot.
    private static func color(for raw: String) -> Color {
        switch raw.uppercased() {
        case "RESTAURANTS":   return Color(red: 0.30, green: 0.69, blue: 0.42)
        case "SUBSCRIPTIONS": return Color(red: 0.63, green: 0.42, blue: 0.84)
        case "GROCERIES":     return Color(red: 0.49, green: 0.70, blue: 0.26)
        case "LOANS":         return Color(red: 0.90, green: 0.22, blue: 0.21)
        case "CLOTHING":      return Color(red: 0.93, green: 0.25, blue: 0.48)
        case "INCOME":        return Color(red: 0.15, green: 0.65, blue: 0.60)
        case "TRANSFER", "TRANSFERS": return Color(red: 0.26, green: 0.65, blue: 0.96)
        case "PERSONAL CARE": return Color(red: 1.00, green: 0.72, blue: 0.30)
        case "ENTERTAINMENT": return Color(red: 1.00, green: 0.66, blue: 0.15)
        case "TRANSPORT":     return Color(red: 0.40, green: 0.85, blue: 0.95)
        case "SHOPPING":      return Color(red: 0.95, green: 0.55, blue: 0.32)
        case "FEES":          return Color(red: 0.55, green: 0.43, blue: 0.39)
        default:              return Color(red: 0.47, green: 0.56, blue: 0.61)
        }
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d"
        return f
    }()

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
}
