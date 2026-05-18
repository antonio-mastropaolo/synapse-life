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
                    if let focused = focusedBucket {
                        // Exploded mode: the tapped card takes over the
                        // grid slot entirely. Closing the panel returns
                        // to the grid.
                        expandedPanel(bucket: focused, tokens: tokens)
                    } else {
                        categoryGrid(tokens: tokens)
                    }
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

    /// The single category currently shown in exploded mode. We treat
    /// the original `expandedCategories` set as a stack-of-one for
    /// this entry point — taking the first matching bucket so only
    /// one explodes at a time.
    private var focusedBucket: CategoryBucket? {
        guard let name = expandedCategories.first else { return nil }
        return categoryBuckets.first(where: { $0.name == name })
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

    // MARK: - 2. Category Grid (expandable)
    //
    // The grid is a 4-column LazyVGrid of compact "summary" cards. Tap
    // a card and that category gets promoted to a full-width row
    // beneath the cards row it lived in, with the transaction list
    // rendered inline — same data as the (now-removed) BY CATEGORY
    // section, just attached to the tile so the eye doesn't have to
    // jump down the page.

    private func categoryGrid(tokens: TokenSet) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CATEGORIES · TAP A CARD TO EXPLODE IT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if !expandedCategories.isEmpty {
                    Button {
                        expandedCategories.removeAll()
                    } label: {
                        Text("Collapse all")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(categoryBuckets) { bucket in
                    categoryCard(bucket: bucket, tokens: tokens)
                }
            }
        }
    }

    private func categoryCard(bucket: CategoryBucket, tokens: TokenSet) -> some View {
        let pct = totalSpend > 0 ? (bucket.total / totalSpend) * 100 : 0
        let isExpanded = expandedCategories.contains(bucket.name)
        return Button {
            if isExpanded {
                _ = expandedCategories.remove(bucket.name)
            } else {
                expandedCategories.insert(bucket.name)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
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
                HStack(spacing: 4) {
                    Text("\(bucket.transactions.count) transactions")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Spacer()
                    Image(systemName: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(bucket.color)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isExpanded ? bucket.color.opacity(0.10) : tokens.surface.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(bucket.color.opacity(isExpanded ? 0.65 : 0.30), lineWidth: isExpanded ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transactions.category.\(bucket.name)")
    }

    // MARK: - Expanded panel
    //
    // Rendered full-width below the grid. Stats strip on top (count,
    // avg, largest), transactions list below with real merchant
    // icons resolved through `MerchantLogoView`.

    private func expandedPanel(bucket: CategoryBucket, tokens: TokenSet) -> some View {
        let borderColor: Color = bucket.color.opacity(0.45)
        return VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Circle().fill(bucket.color).frame(width: 12, height: 12)
                Text(bucket.name)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("\(bucket.transactions.count) transactions")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text(bucket.total.formatted(.currency(code: "USD")))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Button {
                    _ = expandedCategories.remove(bucket.name)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                .buttonStyle(.plain)
            }

            // ---- Stat strip (compact, top row) ----
            HStack(spacing: 20) {
                statTile(label: "Average", value: averageString(for: bucket), tokens: tokens)
                statTile(label: "Largest", value: largestString(for: bucket), tokens: tokens)
                statTile(label: "Most active day", value: peakDayString(for: bucket), tokens: tokens)
                statTile(label: "Share of spend",
                         value: String(format: "%.0f%%",
                             totalSpend > 0
                                 ? NSDecimalNumber(decimal: (bucket.total / totalSpend) * 100).doubleValue
                                 : 0),
                         tokens: tokens)
            }

            // ---- AI signals row ----
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.69, blue: 0.22))
                Text("AI SIGNALS · \(bucket.name.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text("SAMPLE")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                    )
            }
            aiSignalsGrid(bucket: bucket, tokens: tokens)

            // ---- Transactions list ----
            Text("TRANSACTIONS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(bucket.transactions.sorted(by: { $0.date > $1.date })) { tx in
                    expandedTransactionRow(tx, bucket: bucket, tokens: tokens)
                    Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
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
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private func statTile(label: String, value: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandedTransactionRow(_ tx: Models.Transaction, bucket: CategoryBucket, tokens: TokenSet) -> some View {
        HStack(spacing: 14) {
            MerchantLogoView(
                merchant: tx.name,
                fallbackColor: bucket.color,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
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
                .foregroundStyle((tx.amount ?? 0) > 0 ? Color(red: 0.34, green: 0.78, blue: 0.50) : tokens.foregroundPrimary.color)
        }
        .padding(.vertical, 10)
    }

    private var orderedExpanded: [CategoryBucket] {
        categoryBuckets.filter { expandedCategories.contains($0.name) }
    }

    private func averageString(for bucket: CategoryBucket) -> String {
        guard !bucket.transactions.isEmpty else { return "—" }
        let avg = bucket.total / Decimal(bucket.transactions.count)
        return avg.formatted(.currency(code: "USD"))
    }

    private func largestString(for bucket: CategoryBucket) -> String {
        let largest = bucket.transactions.map { abs($0.amount ?? 0) }.max() ?? 0
        return largest.formatted(.currency(code: "USD"))
    }

    private func peakDayString(for bucket: CategoryBucket) -> String {
        guard let peakIdx = bucket.dailyTotals.indices.max(by: {
            bucket.dailyTotals[$0] < bucket.dailyTotals[$1]
        }) else { return "—" }
        let days = constellationDays
        guard peakIdx < days.count else { return "—" }
        guard let d = Self.keyFormatter.date(from: days[peakIdx]) else { return "—" }
        return Self.shortDate.string(from: d)
    }

    // MARK: - AI signals
    //
    // Six tiles surfaced when a category card explodes. All derived
    // locally from the bucket + 14-day window for now (deterministic,
    // free, instant); the integrator can swap any tile to a real LLM
    // call later by replacing the body of the corresponding helper.
    // Every tile carries a tone color (good / warning / neutral) so
    // the eye can scan the grid for red flags.

    private struct AISignal: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tone: Color
    }

    private func aiSignalsGrid(bucket: CategoryBucket, tokens: TokenSet) -> some View {
        let cols = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        let signals = aiSignals(for: bucket)
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(signals) { signal in
                aiSignalTile(signal: signal, tokens: tokens)
            }
        }
    }

    private func aiSignalTile(signal: AISignal, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: signal.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(signal.tone)
                Text(signal.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            Text(signal.detail)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(signal.tone.opacity(0.30), lineWidth: 1)
        )
    }

    private func aiSignals(for bucket: CategoryBucket) -> [AISignal] {
        let good   = Color(red: 0.34, green: 0.78, blue: 0.50)
        let warn   = Color(red: 1.00, green: 0.69, blue: 0.22)
        let neut   = Color(red: 0.27, green: 0.83, blue: 0.89)
        let alert  = Color(red: 0.94, green: 0.33, blue: 0.56)

        // 1. Trend vs typical baseline (derived from this bucket vs
        // the median 14-day pace across all categories).
        let typical = max(totalSpend / Decimal(max(categoryBuckets.count, 1)), 1)
        let ratio = NSDecimalNumber(decimal: bucket.total / typical).doubleValue
        let pct = Int((ratio - 1.0) * 100)
        let trend: AISignal = {
            if pct > 25 {
                return AISignal(
                    icon: "arrow.up.right",
                    title: "Trend vs typical",
                    detail: "\(bucket.name) is \(pct)% higher than your typical 14-day baseline. Largest contributor to that delta: \(topMerchant(for: bucket)).",
                    tone: warn
                )
            } else if pct < -15 {
                return AISignal(
                    icon: "arrow.down.right",
                    title: "Trend vs typical",
                    detail: "\(bucket.name) is \(abs(pct))% lower than your typical pace. Quiet stretch — most categories see at least one charge per 4 days.",
                    tone: good
                )
            } else {
                return AISignal(
                    icon: "equal.circle",
                    title: "Trend vs typical",
                    detail: "\(bucket.name) is tracking within \(abs(pct))% of your typical baseline. No active deviation.",
                    tone: neut
                )
            }
        }()

        // 2. Anomaly / outlier.
        let amounts = bucket.transactions.map {
            abs((($0.amount as NSDecimalNumber?) ?? 0).doubleValue)
        }
        let avg = amounts.isEmpty ? 0 : amounts.reduce(0, +) / Double(amounts.count)
        let largest = amounts.max() ?? 0
        let outlierRatio = avg > 0 ? largest / avg : 0
        let outlierTx = bucket.transactions.max(by: {
            abs((($0.amount as NSDecimalNumber?) ?? 0).doubleValue) <
            abs((($1.amount as NSDecimalNumber?) ?? 0).doubleValue)
        })
        let anomaly: AISignal = {
            if outlierRatio >= 1.8, let tx = outlierTx {
                return AISignal(
                    icon: "exclamationmark.triangle.fill",
                    title: "Outlier detected",
                    detail: "Largest charge (\(tx.name.prefix(28))) is \(String(format: "%.1fx", outlierRatio)) the category's running average. Worth a glance.",
                    tone: alert
                )
            } else {
                return AISignal(
                    icon: "checkmark.shield",
                    title: "No outliers",
                    detail: "Largest charge is \(String(format: "%.1fx", outlierRatio)) the average — within the normal range for this category.",
                    tone: good
                )
            }
        }()

        // 3. Forecast: project month-end at current pace.
        let dailyAvg = NSDecimalNumber(decimal: bucket.total / 14).doubleValue
        let monthProj = Int(dailyAvg * 30)
        let forecast = AISignal(
            icon: "calendar.badge.clock",
            title: "Month-end projection",
            detail: "On this 14-day pace, \(bucket.name) lands near $\(formatThousandsInt(monthProj)) by the close of a 30-day window. \(monthProj > 500 ? "Set a budget if this category matters." : "Modest spend — likely stays in range.")",
            tone: neut
        )

        // 4. Merchant concentration.
        let merchants = Dictionary(grouping: bucket.transactions) { tx -> String in
            String(tx.name.prefix(20))
        }
        let largestMerchant = merchants.max(by: { lhs, rhs in
            lhs.value.reduce(0.0) { $0 + abs((($1.amount as NSDecimalNumber?) ?? 0).doubleValue) }
            <
            rhs.value.reduce(0.0) { $0 + abs((($1.amount as NSDecimalNumber?) ?? 0).doubleValue) }
        })
        let concentration: AISignal = {
            guard let (name, txs) = largestMerchant else {
                return AISignal(
                    icon: "circle.grid.2x1",
                    title: "Merchant mix",
                    detail: "No data available.",
                    tone: neut
                )
            }
            let mTotal = txs.reduce(0.0) { $0 + abs((($1.amount as NSDecimalNumber?) ?? 0).doubleValue) }
            let bucketTotalD = NSDecimalNumber(decimal: bucket.total).doubleValue
            let mPct = bucketTotalD > 0 ? Int(100 * mTotal / bucketTotalD) : 0
            return AISignal(
                icon: "circle.grid.2x1",
                title: "Merchant concentration",
                detail: "\(mPct)% of this category goes to one merchant: \(name.trimmingCharacters(in: .whitespaces)). \(mPct >= 70 ? "Heavy concentration — worth reviewing the relationship." : "Diversified across multiple merchants.")",
                tone: mPct >= 70 ? warn : neut
            )
        }()

        // 5. Behaviour pattern — day-of-week clustering.
        let cal = Calendar.current
        var dowCounts: [Int: Int] = [:]
        for tx in bucket.transactions {
            let dow = cal.component(.weekday, from: tx.date)
            dowCounts[dow, default: 0] += 1
        }
        let dominantDOW = dowCounts.max(by: { $0.value < $1.value })
        let dowLabel: String = {
            guard let day = dominantDOW?.key else { return "—" }
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return names[(day - 1 + 7) % 7]
        }()
        let dowPct: Int = {
            guard let d = dominantDOW, !bucket.transactions.isEmpty else { return 0 }
            return Int(100.0 * Double(d.value) / Double(bucket.transactions.count))
        }()
        let pattern = AISignal(
            icon: "waveform.path.ecg",
            title: "Day-of-week pattern",
            detail: dominantDOW == nil
                ? "Not enough data to detect a cadence yet."
                : "\(dowPct)% of \(bucket.name) charges land on \(dowLabel). \(dowPct >= 60 ? "Strong weekly cadence — automatable." : "No strong cadence — spend is spread across the week.")",
            tone: dowPct >= 60 ? neut : Color(red: 0.58, green: 0.66, blue: 0.74)
        )

        // 6. AI recommendation.
        let recommendation: AISignal = {
            if pct > 30 {
                return AISignal(
                    icon: "sparkles",
                    title: "AI suggests",
                    detail: "Cap \(bucket.name) at $\(formatThousandsInt(Int(NSDecimalNumber(decimal: typical * Decimal(1.2)).doubleValue))) for the next 14 days. Reach the previous average and you free $\(formatThousandsInt(Int(ratio - 1.0) * Int(NSDecimalNumber(decimal: typical).doubleValue))) for goal progress.",
                    tone: warn
                )
            } else if let (name, _) = largestMerchant, outlierRatio >= 1.8 {
                return AISignal(
                    icon: "sparkles",
                    title: "AI suggests",
                    detail: "Open the largest charge (\(name.trimmingCharacters(in: .whitespaces))) and verify it's expected. Outliers are the cheapest place to recover budget.",
                    tone: warn
                )
            } else {
                return AISignal(
                    icon: "sparkles",
                    title: "AI suggests",
                    detail: "\(bucket.name) is healthy. No suggested action — keep doing what you're doing.",
                    tone: good
                )
            }
        }()

        return [trend, anomaly, forecast, concentration, pattern, recommendation]
    }

    private func topMerchant(for bucket: CategoryBucket) -> String {
        let grouped = Dictionary(grouping: bucket.transactions) {
            String($0.name.prefix(20))
        }
        let top = grouped.max(by: { lhs, rhs in
            lhs.value.reduce(0.0) { $0 + abs((($1.amount as NSDecimalNumber?) ?? 0).doubleValue) }
            <
            rhs.value.reduce(0.0) { $0 + abs((($1.amount as NSDecimalNumber?) ?? 0).doubleValue) }
        })?.key ?? "—"
        return top.trimmingCharacters(in: .whitespaces)
    }

    private func formatThousandsInt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
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
