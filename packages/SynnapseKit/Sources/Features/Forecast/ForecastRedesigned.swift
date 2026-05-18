import SwiftUI
import Charts
import DesignSystem
import Models
import SynnapseCharts

/// Rich redesign of the Forecast (cash-flow) surface.
///
/// Replaces the minimum-viable [[ForecastView]] with the same layered
/// structure [[RecurringsRedesigned]] established for the AI++ wedge:
///
///   1. **Hero** — "Cash flow" title plus three summary tiles
///      (today's balance, end-of-horizon projection, zero-crossing or
///      stays-positive verdict).
///   2. **Big projection chart** — full-width Swift Charts line over
///      the deterministic [[BalanceProjection]] daily series, with a
///      dashed $0 reference rule and a vertical zero-crossing marker
///      when the projection dips through zero in the horizon.
///   3. **AI insights grid** — three 132pt-tall tiles (RUNWAY,
///      BIGGEST UPCOMING HIT, INCOME RHYTHM) carrying the SAMPLE
///      chip in demo mode.
///   4. **Upcoming line items** — week-grouped sections (This week /
///      Next week / Week of MMM d / etc) of every predicted debit and
///      credit in the horizon, with [[MerchantLogoView]] avatars,
///      cadence pills, and signed amounts (loss-tinted debits,
///      gain-tinted credits).
///   5. **What-if strip** — three quick-scenario chips that shift a
///      locally-held projection number, demonstrating the surface
///      that will eventually recompute against the projector. The
///      stub is clearly marked SAMPLE.
///
/// Everything on the surface is derived from `ForecastViewModel`'s
/// public API plus a small amount of sample copy for the income
/// rhythm tile (the VM does not expose the next expected payroll
/// deposit as a typed accessor yet — see the report).
@MainActor
public struct ForecastRedesigned: View {

    @Bindable private var viewModel: ForecastViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// What-if scenario currently applied to the locally-displayed
    /// projection number. `nil` means we render the unmodified value
    /// from `viewModel.projection.freeCashAtHorizon`. Tapping a
    /// scenario chip toggles it on/off without touching the VM —
    /// real recompute lives behind the same API in a future patch.
    @State private var scenario: WhatIfScenario?

    public init(viewModel: ForecastViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                hero(tokens: tokens)
                if viewModel.projection != nil {
                    projectionChartCard(tokens: tokens)
                    aiInsightsGrid(tokens: tokens)
                    whatIfStrip(tokens: tokens)
                    upcomingLineItems(tokens: tokens)
                } else if viewModel.isLoading {
                    loadingState(tokens: tokens)
                } else if let err = viewModel.lastError {
                    errorState(message: err, tokens: tokens)
                } else {
                    emptyState(tokens: tokens)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("intelligence.forecast.redesigned")
    }

    // MARK: - Hero

    private func hero(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cash flow")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Projected balance across the next \(viewModel.horizonDays) days, derived from your detected recurring charges and income.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                summaryTile(
                    label: "Today's balance",
                    value: formatCurrency(viewModel.projection?.startingChecking ?? 0),
                    tokens: tokens
                )
                summaryTile(
                    label: "\(viewModel.horizonDays)-day projection",
                    value: formatCurrency(displayedProjectionEnd),
                    tokens: tokens
                )
                summaryTile(
                    label: zeroCrossingTileLabel,
                    value: zeroCrossingTileValue,
                    tokens: tokens,
                    tint: zeroCrossingTileTint(tokens: tokens)
                )
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    private func summaryTile(
        label: String,
        value: String,
        tokens: TokenSet,
        tint: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint ?? tokens.foregroundPrimary.color)
                .monospacedDigit()
        }
    }

    /// End-of-horizon projected balance, optionally adjusted by the
    /// currently-applied what-if scenario. We deliberately keep the
    /// adjustment local — the stub is presentational, the real
    /// recompute path will live behind a VM method.
    private var displayedProjectionEnd: Decimal {
        let base = viewModel.projection?.freeCashAtHorizon ?? 0
        guard let scenario else { return base }
        return base + scenario.delta(against: viewModel.projection)
    }

    private var zeroCrossingTileLabel: String {
        viewModel.projection?.projectedZeroDate == nil
            ? "Runway"
            : "Zero-crossing"
    }

    private var zeroCrossingTileValue: String {
        guard let projection = viewModel.projection else { return "—" }
        if let date = projection.projectedZeroDate {
            return Self.shortDayFormatter.string(from: date)
        }
        return "Stays positive"
    }

    private func zeroCrossingTileTint(tokens: TokenSet) -> Color? {
        guard let projection = viewModel.projection else { return nil }
        return projection.projectedZeroDate == nil
            ? tokens.gainAccent.color
            : tokens.lossAccent.color
    }

    // MARK: - Projection chart card

    private func projectionChartCard(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("BALANCE PROJECTION")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if let projection = viewModel.projection {
                    Text("\(projection.dailyBalanceSeries.count) day points")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            projectionChart(tokens: tokens)
                .frame(height: 220)
            chartLegend(tokens: tokens)
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

    /// Inline Swift Charts canvas. We don't reuse [[MoneyLineChart]]
    /// here because we need the $0 reference rule and the
    /// zero-crossing vertical marker — overlays that the shared
    /// chart deliberately does not expose. The geometry is the same
    /// Decimal-bridged-at-the-edge pattern.
    private func projectionChart(tokens: TokenSet) -> some View {
        let series = viewModel.projectionSeries
        let accent = tokens.accent.color
        let lossTint = tokens.lossAccent.color
        let zero = viewModel.projection?.projectedZeroDate
        return Chart {
            ForEach(series) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", (point.amount as NSDecimalNumber).doubleValue),
                    series: .value("Series", "projection")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", (point.amount as NSDecimalNumber).doubleValue),
                    series: .value("Series", "projection")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.32), accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            // Dashed $0 reference rule. Painted last in this block
            // but Swift Charts draws RuleMarks above area marks
            // anyway, so the dashed line reads clearly over the
            // gradient wash.
            RuleMark(y: .value("Zero", 0))
                .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.55))
            // Vertical zero-crossing marker — only when the
            // deterministic projection actually dips through zero in
            // the horizon. We tint it loss-red because the crossing
            // is the event the user is being warned about.
            if let zero {
                RuleMark(x: .value("Zero crossing", zero))
                    .lineStyle(.init(lineWidth: 1.5, dash: [3, 2]))
                    .foregroundStyle(lossTint.opacity(0.75))
                    .annotation(position: .top, alignment: .leading) {
                        Text(Self.shortDayFormatter.string(from: zero))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(lossTint.opacity(0.18))
                            )
                            .foregroundStyle(lossTint)
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        let formatted = Decimal(raw).formatted(
                            .currency(code: "USD").precision(.fractionLength(0))
                        )
                        Text(formatted)
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 9, design: .monospaced))
            }
        }
    }

    private func chartLegend(tokens: TokenSet) -> some View {
        HStack(spacing: 16) {
            legendDot(color: tokens.accent.color, label: "Projected balance", tokens: tokens)
            legendDash(color: tokens.foregroundSecondary.color.opacity(0.55), label: "$0 line", tokens: tokens)
            if viewModel.projection?.projectedZeroDate != nil {
                legendDash(color: tokens.lossAccent.color, label: "Zero-crossing", tokens: tokens)
            }
            Spacer()
        }
    }

    private func legendDot(color: Color, label: String, tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    private func legendDash(color: Color, label: String, tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 12, height: 1.5)
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    // MARK: - AI insights grid

    private func aiInsightsGrid(tokens: TokenSet) -> some View {
        let cols = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
                Text("AI INSIGHTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(insights) { tile in
                    insightTile(tile, tokens: tokens)
                }
            }
        }
    }

    private struct InsightTile: Identifiable {
        let id = UUID()
        let kind: Kind
        let icon: String
        let title: String
        let headline: String
        let detail: String
        let tone: Color
        let isSample: Bool
        enum Kind { case runway, biggestHit, incomeRhythm }
    }

    private var insights: [InsightTile] {
        let good = Color(red: 0.34, green: 0.78, blue: 0.50)
        let warn = Color(red: 1.00, green: 0.69, blue: 0.22)
        let neut = Color(red: 0.27, green: 0.83, blue: 0.89)

        let runway = runwayInsight(good: good, warn: warn)
        let biggest = biggestHitInsight(warn: warn)
        let income = incomeRhythmInsight(neut: neut)

        return [runway, biggest, income]
    }

    private func runwayInsight(good: Color, warn: Color) -> InsightTile {
        let projection = viewModel.projection
        if let days = projection?.runwayDays, let zero = projection?.projectedZeroDate {
            return InsightTile(
                kind: .runway,
                icon: "hourglass",
                title: "Runway",
                headline: "\(days) day\(days == 1 ? "" : "s")",
                detail: "At the current burn rate, checking dips below zero on \(Self.shortDayFormatter.string(from: zero)). Pre-fund before that date to dodge overdraft.",
                tone: warn,
                isSample: false
            )
        }
        let safeWord = projection == nil ? "—" : "Stays positive"
        let lowest = projection.map { formatCurrency($0.lowestProjectedBalance) } ?? "—"
        let lowestDate = projection.map { Self.shortDayFormatter.string(from: $0.lowestProjectedBalanceDate) } ?? "—"
        return InsightTile(
            kind: .runway,
            icon: "checkmark.shield.fill",
            title: "Runway",
            headline: safeWord,
            detail: "Lowest projected balance is \(lowest) on \(lowestDate) — the dip never crosses zero within the \(viewModel.horizonDays)-day horizon.",
            tone: good,
            isSample: false
        )
    }

    private func biggestHitInsight(warn: Color) -> InsightTile {
        if let big = viewModel.projection?.biggestSingleCharge {
            return InsightTile(
                kind: .biggestHit,
                icon: "creditcard.circle.fill",
                title: "Biggest upcoming hit",
                headline: formatCurrency(big.amount),
                detail: "\(big.merchant) on \(Self.shortDayFormatter.string(from: big.date)). Plan checking to clear this line without dipping into a buffer.",
                tone: warn,
                isSample: false
            )
        }
        return InsightTile(
            kind: .biggestHit,
            icon: "creditcard.circle.fill",
            title: "Biggest upcoming hit",
            headline: "$340",
            detail: "Sample BNPL Payment lands on May 30 — the largest single recurring outflow in the window.",
            tone: warn,
            isSample: true
        )
    }

    private func incomeRhythmInsight(neut: Color) -> InsightTile {
        // The VM exposes credit events but no first-class "next
        // expected payroll" accessor. We pick the earliest credit in
        // the horizon as a stand-in; if none is detected we fall
        // back to obviously-sample copy so the tile still reads.
        if let next = viewModel.creditEvents.min(by: { $0.date < $1.date }) {
            return InsightTile(
                kind: .incomeRhythm,
                icon: "arrow.down.left.circle.fill",
                title: "Income rhythm",
                headline: formatCurrency(next.amount),
                detail: "Next expected deposit: \(next.merchant) on \(Self.shortDayFormatter.string(from: next.date)). Cadence-confirmed from your recurring credits.",
                tone: neut,
                isSample: false
            )
        }
        return InsightTile(
            kind: .incomeRhythm,
            icon: "arrow.down.left.circle.fill",
            title: "Income rhythm",
            headline: "$3,460",
            detail: "Next expected deposit: Sample Payroll on May 30. Cadence cleared at bi-weekly across the last 6 weeks.",
            tone: neut,
            isSample: true
        )
    }

    private func insightTile(_ tile: InsightTile, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: tile.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tile.tone)
                Text(tile.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if tile.isSample {
                    sampleChip
                }
            }
            Text(tile.headline)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
            Text(tile.detail)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tile.tone.opacity(0.30), lineWidth: 1)
        )
    }

    private var sampleChip: some View {
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

    // MARK: - What-if strip

    private enum WhatIfScenario: String, CaseIterable, Identifiable {
        case skipBiggest
        case addIncome
        case cutSubscriptions

        var id: String { rawValue }

        var label: String {
            switch self {
            case .skipBiggest:       return "Skip biggest bill"
            case .addIncome:         return "Add $500 income"
            case .cutSubscriptions:  return "Cut subscriptions 25%"
            }
        }

        var icon: String {
            switch self {
            case .skipBiggest:       return "minus.circle.fill"
            case .addIncome:         return "plus.circle.fill"
            case .cutSubscriptions:  return "scissors"
            }
        }

        /// Presentation-only delta against the projection. Real
        /// recompute will route through the projector — see the
        /// section comment up top.
        func delta(against projection: BalanceProjection?) -> Decimal {
            switch self {
            case .skipBiggest:
                return projection?.biggestSingleCharge?.amount ?? 0
            case .addIncome:
                return 500
            case .cutSubscriptions:
                // 25% of total debits as a coarse proxy for "cut
                // every subscription by a quarter". The real path
                // would re-run the projector with the matching
                // recurring set scaled down.
                let total = projection?.totalDebits ?? 0
                return (total * Decimal(0.25))
            }
        }
    }

    private func whatIfStrip(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.63, green: 0.42, blue: 0.84))
                Text("WHAT IF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                sampleChip
            }
            HStack(spacing: 10) {
                ForEach(WhatIfScenario.allCases) { s in
                    whatIfButton(s, tokens: tokens)
                }
                Spacer()
            }
            if let scenario {
                whatIfReadout(scenario, tokens: tokens)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func whatIfButton(_ s: WhatIfScenario, tokens: TokenSet) -> some View {
        let isActive = scenario == s
        let tint = Color(red: 0.63, green: 0.42, blue: 0.84)
        return Button {
            scenario = isActive ? nil : s
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(s.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isActive ? Color.white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? tint : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(isActive ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func whatIfReadout(_ s: WhatIfScenario, tokens: TokenSet) -> some View {
        let base = viewModel.projection?.freeCashAtHorizon ?? 0
        let delta = s.delta(against: viewModel.projection)
        let next = base + delta
        let arrow = delta >= 0 ? "arrow.up.right" : "arrow.down.right"
        let tint = delta >= 0 ? tokens.gainAccent.color : tokens.lossAccent.color
        return HStack(spacing: 10) {
            Image(systemName: arrow)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text("Projected end-of-horizon balance")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(formatCurrency(base))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .strikethrough()
                .monospacedDigit()
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(formatCurrency(next))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .monospacedDigit()
            Spacer()
            Button {
                scenario = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
    }

    // MARK: - Upcoming line items (30 days, week-grouped)

    private func upcomingLineItems(tokens: TokenSet) -> some View {
        let groups = weeklyGroups
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text("UPCOMING · NEXT \(viewModel.horizonDays) DAYS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                let totalCount = groups.reduce(0) { $0 + $1.flows.count }
                Text("\(totalCount) line\(totalCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            if groups.isEmpty {
                Text("No predicted credits or debits in this window.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .padding(.vertical, 12)
            } else {
                ForEach(groups) { group in
                    weekCard(group, tokens: tokens)
                }
            }
        }
    }

    /// One Sunday-anchored week of scheduled flows, sorted by date.
    private struct WeekGroup: Identifiable {
        let id: Date  // start of the week (Sunday)
        let label: String
        let flows: [ScheduledFlow]
        var net: Decimal {
            flows.reduce(Decimal.zero) { acc, f in
                f.direction == .credit ? acc + f.amount : acc - f.amount
            }
        }
    }

    private var weeklyGroups: [WeekGroup] {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        // Sunday is the start-of-week anchor — gregorian default
        // matches what RecurringsRedesigned uses for the calendar
        // strip elsewhere on the surface.
        let weekOfToday = startOfWeek(today, calendar: cal)
        let allFlows = (viewModel.predictedChargesList + viewModel.creditEvents)
            .sorted { $0.date < $1.date }
        var buckets: [Date: [ScheduledFlow]] = [:]
        for flow in allFlows {
            let key = startOfWeek(cal.startOfDay(for: flow.date), calendar: cal)
            buckets[key, default: []].append(flow)
        }
        let sortedKeys = buckets.keys.sorted()
        return sortedKeys.map { key in
            let label: String
            let weeksFromToday = cal.dateComponents([.weekOfYear], from: weekOfToday, to: key).weekOfYear ?? 0
            switch weeksFromToday {
            case ...0: label = "This week"
            case 1:    label = "Next week"
            default:   label = "Week of \(Self.shortDayFormatter.string(from: key))"
            }
            return WeekGroup(id: key, label: label, flows: buckets[key] ?? [])
        }
    }

    private func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 1  // Sunday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    private func weekCard(_ group: WeekGroup, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(group.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("\(group.flows.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tokens.foregroundSecondary.color.opacity(0.12))
                    )
                Spacer()
                Text(formatSignedCurrency(group.net))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(group.net >= 0 ? tokens.gainAccent.color : tokens.lossAccent.color)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            VStack(spacing: 0) {
                ForEach(group.flows) { flow in
                    flowRow(flow, tokens: tokens)
                    if flow.id != group.flows.last?.id {
                        Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func flowRow(_ flow: ScheduledFlow, tokens: TokenSet) -> some View {
        let isDebit = flow.direction == .debit
        let catColor = categoryColor(flow.category)
        let amountTint = isDebit ? tokens.lossAccent.color : tokens.gainAccent.color
        return HStack(alignment: .center, spacing: 14) {
            MerchantLogoView(
                merchant: flow.merchant,
                fallbackColor: catColor,
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(flow.merchant)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(cadencePillLabel(for: flow).uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(catColor.opacity(0.18))
                        )
                        .foregroundStyle(catColor)
                }
                Text("\(isDebit ? "Debit" : "Credit") · \(Self.longDayFormatter.string(from: flow.date))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            Text(formatSignedFlowAmount(flow))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(amountTint)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// We don't carry the recurring-detection cadence on
    /// `ScheduledFlow`, so the pill reads "Debit" / "Credit" only.
    /// When the projector starts threading cadence through, this is
    /// where the weekly / monthly / yearly tag lands.
    private func cadencePillLabel(for flow: ScheduledFlow) -> String {
        flow.direction == .debit ? "Outflow" : "Inflow"
    }

    // MARK: - States

    private func loadingState(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Projecting your cash flow…")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.vertical, 24)
    }

    private func errorState(message: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Forecast unavailable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.vertical, 24)
    }

    private func emptyState(tokens: TokenSet) -> some View {
        Text("No forecast yet. Connect a checking account so Synapse can detect your recurrings and project cash flow forward.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(tokens.foregroundSecondary.color)
            .padding(.vertical, 24)
    }

    // MARK: - Formatting / category color

    private func categoryColor(_ id: CategoryID) -> Color {
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

    private func formatCurrency(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        let mag = (amount as NSDecimalNumber).doubleValue
        nf.maximumFractionDigits = abs(mag) >= 100 ? 0 : 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0"
    }

    private func formatSignedCurrency(_ amount: Decimal) -> String {
        let prefix = amount >= 0 ? "+" : "−"
        let absVal = amount >= 0 ? amount : -amount
        return prefix + formatCurrency(absVal)
    }

    /// Flow amounts in `ScheduledFlow` are always positive — the sign
    /// is carried by `direction`. The list paints debits as negative
    /// (red) and credits as positive (green) so the reader can scan
    /// inflows and outflows by tint alone.
    private func formatSignedFlowAmount(_ flow: ScheduledFlow) -> String {
        let prefix = flow.direction == .credit ? "+" : "−"
        return prefix + formatCurrency(flow.amount)
    }

    private static let shortDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM d"
        return df
    }()

    private static let longDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, MMM d"
        return df
    }()
}
