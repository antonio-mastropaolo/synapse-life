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

    // MARK: - 1. Daily Spend Composition
    //
    // Replaced the original scattered-bubble "constellation" with a
    // sequence of 14 horizontal stacked bars, one per day. Each bar's
    // total width is proportional to that day's spend (relative to
    // the heaviest day in the period); each segment in the bar is one
    // category, sized by spend. Far more legible than bubbles: the
    // eye reads the rows top-to-bottom and sees both the day's size
    // AND its composition at a glance.

    private func constellationCard(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DAILY SPEND · LAST 14 DAYS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text("Each row is one day. Width = total spend. Segments = categories.")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            dailyComposition(tokens: tokens)
            categoryLegend(tokens: tokens)
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

    private func dailyComposition(tokens: TokenSet) -> some View {
        let rows = dailyComposed
        let peak = rows.map(\.total).max() ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .frame(width: 56, alignment: .trailing)

                    GeometryReader { geo in
                        let widthScale = geo.size.width
                        let totalWidth = widthScale * (row.total == 0 ? 0 : row.total / peak)
                        HStack(spacing: 1) {
                            ForEach(row.segments) { seg in
                                let segWidth = totalWidth * (row.total == 0 ? 0 : seg.amount / row.total)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(seg.color)
                                    .frame(width: max(segWidth, seg.amount > 0 ? 2 : 0))
                            }
                            if row.total == 0 {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(tokens.foregroundSecondary.color.opacity(0.10))
                                    .frame(width: 6)
                            }
                        }
                        .frame(height: 16)
                    }
                    .frame(height: 16)

                    Text(row.total == 0 ? "—" : formatCompactDollar(row.total))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(row.total == 0 ? tokens.foregroundSecondary.color : tokens.foregroundPrimary.color)
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    private func categoryLegend(tokens: TokenSet) -> some View {
        FlowingHStack(spacing: 14) {
            ForEach(categoryBuckets.prefix(8)) { bucket in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(bucket.color)
                        .frame(width: 10, height: 10)
                    Text(bucket.name.capitalized)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
        }
    }

    private func formatCompactDollar(_ value: Double) -> String {
        if value >= 1000 { return String(format: "$%.1fK", value / 1000) }
        return String(format: "$%.0f", value)
    }

    private struct DailyRow: Identifiable {
        let id = UUID()
        let label: String
        let total: Double
        let segments: [DailySegment]
    }

    private struct DailySegment: Identifiable {
        let id = UUID()
        let color: Color
        let amount: Double
    }

    private var dailyComposed: [DailyRow] {
        let cal = Calendar.current
        let days = constellationDays.reversed()  // newest first reads top-down
        return days.map { dayKey in
            // Per-category amount on this day
            var byCat: [(name: String, color: Color, amount: Double)] = []
            for bucket in categoryBuckets {
                let total = bucket.transactions.reduce(0.0) { acc, tx in
                    let txKey = Self.keyFormatter.string(from: cal.startOfDay(for: tx.date))
                    if txKey == dayKey {
                        return acc + abs((tx.amount as NSDecimalNumber?)?.doubleValue ?? 0)
                    }
                    return acc
                }
                if total > 0 {
                    byCat.append((bucket.name, bucket.color, total))
                }
            }
            byCat.sort { $0.amount > $1.amount }
            let segs = byCat.map { DailySegment(color: $0.color, amount: $0.amount) }
            return DailyRow(
                label: shortDayLabel(dayKey),
                total: byCat.reduce(0.0) { $0 + $1.amount },
                segments: segs
            )
        }
    }

    private func shortDayLabel(_ key: String) -> String {
        guard let d = Self.keyFormatter.date(from: key) else { return key }
        return Self.shortDayDow.string(from: d).uppercased()
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

    private static let shortDayDow: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE M/d"
        return f
    }()
}

/// Minimal wrapping HStack used for the category-color legend. Lays
/// children left-to-right, breaks to a new row when the available
/// width runs out. Substantially simpler than the AnyLayout dance —
/// we only need it for ~8 small chips. Not @MainActor because the
/// Layout protocol's methods are nonisolated.
private struct FlowingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
