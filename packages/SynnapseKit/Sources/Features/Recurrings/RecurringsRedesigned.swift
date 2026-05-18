import SwiftUI
import DesignSystem
import Models

/// Rich redesign of the Recurrings surface. Replaces the flat
/// sectioned list with four stacked visual layers:
///
/// 1. **Hero summary** — total count, monthly equivalent, next-up
///    relative date.
/// 2. **30-day calendar timeline** — horizontal strip of day cells,
///    one per upcoming day. Each cell shows colored dots for the
///    recurrings billing that day (color = category). Lets the eye
///    see clustering and gaps at a glance.
/// 3. **AI insight tiles** — three dense observations (week's hit,
///    biggest line, cadence cluster).
/// 4. **Filter chips + card-style rows** — filter by cadence (All /
///    Weekly / Bi-weekly / Monthly / Quarterly / Yearly), then
///    sectioned rows (Detected / Confirmed / Ignored) using
///    `MerchantLogoView` for real brand logos.
@MainActor
public struct RecurringsRedesigned: View {

    @Bindable private var viewModel: RecurringsViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var selection: String?
    @State private var expandedSections: Set<String> = ["detected", "confirmed"]
    @State private var cadenceFilter: CadenceFilter = .all

    public init(viewModel: RecurringsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header(tokens: tokens)
                if !viewModel.recurrings.isEmpty {
                    calendarStrip(tokens: tokens)
                    aiInsights(tokens: tokens)
                    filterChips(tokens: tokens)
                    sectionedList(tokens: tokens)
                } else {
                    emptyState(tokens: tokens)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("more.recurrings")
    }

    // MARK: - Header

    private func header(tokens: TokenSet) -> some View {
        let upcoming = upcomingTotalIn(days: 7)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Recurrings")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                summaryTile(
                    label: "Detected",
                    value: "\(viewModel.recurrings.count)",
                    tokens: tokens
                )
                summaryTile(
                    label: "Monthly equivalent",
                    value: formatCurrency(viewModel.monthlyEquivalentTotal),
                    tokens: tokens
                )
                summaryTile(
                    label: "Next 7 days",
                    value: formatCurrency(upcoming),
                    tokens: tokens
                )
                Spacer()
            }
        }
    }

    private func summaryTile(label: String, value: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
        }
    }

    // MARK: - Calendar strip (30 days)

    private func calendarStrip(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEXT 30 DAYS · UPCOMING CHARGES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text("Dots = recurring charges. Color = category.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            calendarRow(tokens: tokens)
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

    private func calendarRow(tokens: TokenSet) -> some View {
        let cells = calendarCells
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(cells) { cell in
                    calendarCell(cell, tokens: tokens)
                }
            }
        }
    }

    private struct CalendarCell: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let dowLabel: String
        let isToday: Bool
        let isMonthStart: Bool
        let charges: [(color: Color, amount: Decimal, merchant: String)]
        var totalAmount: Decimal { charges.reduce(0) { $0 + $1.amount } }
    }

    private func calendarCell(_ cell: CalendarCell, tokens: TokenSet) -> some View {
        VStack(spacing: 4) {
            // Day label
            Text(cell.dayLabel)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
            Text(cell.dowLabel)
                .font(.system(size: 10, weight: cell.isToday ? .bold : .medium, design: .monospaced))
                .foregroundStyle(cell.isToday
                    ? Color(red: 1.0, green: 0.69, blue: 0.22)
                    : tokens.foregroundPrimary.color)
            // Dot stack
            VStack(spacing: 3) {
                if cell.charges.isEmpty {
                    Circle()
                        .fill(tokens.foregroundSecondary.color.opacity(0.10))
                        .frame(width: 4, height: 4)
                } else {
                    ForEach(Array(cell.charges.prefix(3).enumerated()), id: \.offset) { _, ch in
                        Circle()
                            .fill(ch.color)
                            .frame(width: 7, height: 7)
                    }
                    if cell.charges.count > 3 {
                        Text("+\(cell.charges.count - 3)")
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                }
            }
            .frame(height: 36, alignment: .top)
            // Amount
            if cell.totalAmount > 0 {
                Text(formatCompactDollar(cell.totalAmount))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            } else {
                Text("—")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.4))
            }
        }
        .frame(width: 32, height: 92)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cell.isToday
                    ? Color(red: 1.0, green: 0.69, blue: 0.22).opacity(0.10)
                    : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(cell.isToday
                    ? Color(red: 1.0, green: 0.69, blue: 0.22).opacity(0.50)
                    : Color.clear,
                    lineWidth: 1)
        )
    }

    private var calendarCells: [CalendarCell] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dayFmt = Self.dayNumberFormatter
        let dowFmt = Self.dowFormatter
        return (0..<30).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let charges = chargesForDay(date)
            let isMonthStart = cal.component(.day, from: date) == 1
            return CalendarCell(
                date: date,
                dayLabel: dayFmt.string(from: date),
                dowLabel: isMonthStart ? dowFmt.string(from: date).uppercased() : dowFmt.string(from: date),
                isToday: offset == 0,
                isMonthStart: isMonthStart,
                charges: charges
            )
        }
    }

    private func chargesForDay(_ day: Date) -> [(color: Color, amount: Decimal, merchant: String)] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        var hits: [(color: Color, amount: Decimal, merchant: String)] = []
        for r in viewModel.recurrings {
            let next = predictedNextOccurrences(for: r)
            for occurrence in next {
                if cal.isDate(occurrence, inSameDayAs: startOfDay) {
                    hits.append((categoryColor(r.category), r.medianAmount, r.merchant))
                }
            }
        }
        return hits
    }

    /// Returns predicted next occurrences within the 30-day window
    /// from the recurring's `predictedNext` rolling forward by cadence.
    private func predictedNextOccurrences(for r: DetectedRecurring) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let horizon = cal.date(byAdding: .day, value: 30, to: today) ?? today
        var result: [Date] = []
        var cursor = r.predictedNext
        // Wind back to the first occurrence at or after today.
        while cursor < today {
            cursor = cal.date(byAdding: .day, value: r.cadenceDays, to: cursor) ?? cursor
        }
        while cursor <= horizon {
            result.append(cursor)
            cursor = cal.date(byAdding: .day, value: r.cadenceDays, to: cursor) ?? cursor
        }
        return result
    }

    private func upcomingTotalIn(days: Int) -> Decimal {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let horizon = cal.date(byAdding: .day, value: days, to: today) else { return 0 }
        var total: Decimal = 0
        for r in viewModel.recurrings {
            for occurrence in predictedNextOccurrences(for: r) where occurrence <= horizon {
                total += r.medianAmount
            }
        }
        return total
    }

    // MARK: - AI insights (3 dense tiles)

    private func aiInsights(tokens: TokenSet) -> some View {
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
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(insightSet) { insight in
                    aiInsightTile(insight, tokens: tokens)
                }
            }
        }
    }

    private struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tone: Color
    }

    private var insightSet: [Insight] {
        let good  = Color(red: 0.34, green: 0.78, blue: 0.50)
        let warn  = Color(red: 1.00, green: 0.69, blue: 0.22)
        let neut  = Color(red: 0.27, green: 0.83, blue: 0.89)

        let upcoming7 = upcomingTotalIn(days: 7)
        let nextBig = viewModel.recurrings.max(by: { $0.medianAmount < $1.medianAmount })
        let monthlies = viewModel.recurrings.filter { $0.cadenceDays == 30 }.count

        return [
            Insight(
                icon: "calendar.badge.clock",
                title: "Next 7 days",
                detail: "\(formatCurrency(upcoming7)) of recurring charges hit in the next week. Pre-fund any account that runs tight by Sunday to dodge overdraft swing.",
                tone: upcoming7 > 200 ? warn : neut
            ),
            Insight(
                icon: "creditcard.circle.fill",
                title: "Biggest line",
                detail: nextBig.map { "\($0.merchant) at \(formatCurrency($0.medianAmount)) every \(cadenceLabel($0.cadenceDays).lowercased()) — accounts for the largest single recurring outflow." } ?? "No detections yet.",
                tone: warn
            ),
            Insight(
                icon: "rectangle.stack.fill",
                title: "Cadence mix",
                detail: "\(monthlies) monthly · \(viewModel.recurrings.filter { $0.cadenceDays == 365 }.count) annual · \(viewModel.recurrings.filter { $0.cadenceDays == 7 || $0.cadenceDays == 14 }.count) weekly/bi-weekly. Monthly-heavy mix is healthy — fewer surprise large hits.",
                tone: good
            )
        ]
    }

    private func aiInsightTile(_ insight: Insight, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: insight.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(insight.tone)
                Text(insight.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            Text(insight.detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
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
                .stroke(insight.tone.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Cadence filter chips

    private enum CadenceFilter: String, CaseIterable, Identifiable {
        case all, weekly, biweekly, monthly, quarterly, yearly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:       return "All"
            case .weekly:    return "Weekly"
            case .biweekly:  return "Bi-weekly"
            case .monthly:   return "Monthly"
            case .quarterly: return "Quarterly"
            case .yearly:    return "Yearly"
            }
        }
        func matches(_ days: Int) -> Bool {
            switch self {
            case .all:       return true
            case .weekly:    return days == 7
            case .biweekly:  return days == 14
            case .monthly:   return days == 30
            case .quarterly: return days == 90
            case .yearly:    return days == 365
            }
        }
    }

    private func filterChips(tokens: TokenSet) -> some View {
        HStack(spacing: 8) {
            ForEach(CadenceFilter.allCases) { f in
                Button {
                    cadenceFilter = f
                } label: {
                    Text(f.label.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(cadenceFilter == f
                            ? Color.white
                            : tokens.foregroundSecondary.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(cadenceFilter == f
                                    ? Color(red: 1.0, green: 0.69, blue: 0.22)
                                    : tokens.foregroundSecondary.color.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Sections

    private func sectionedList(tokens: TokenSet) -> some View {
        let sections = viewModel.sections
        return VStack(alignment: .leading, spacing: 16) {
            sectionCard(id: "detected", title: "Detected", rows: filtered(sections.detected), tokens: tokens, showActions: true)
            sectionCard(id: "confirmed", title: "Confirmed", rows: filtered(sections.confirmed), tokens: tokens, showActions: true)
            sectionCard(id: "ignored", title: "Ignored", rows: filtered(sections.ignored), tokens: tokens, showActions: true)
        }
    }

    private func filtered(_ rows: [DetectedRecurring]) -> [DetectedRecurring] {
        rows.filter { cadenceFilter.matches($0.cadenceDays) }
    }

    private func sectionCard(
        id: String,
        title: String,
        rows: [DetectedRecurring],
        tokens: TokenSet,
        showActions: Bool
    ) -> some View {
        let isExpanded = expandedSections.contains(id)
        let sectionTotal = rows.reduce(Decimal.zero) { $0 + monthlyEquivalent($1) }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded { expandedSections.remove(id) } else { expandedSections.insert(id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("\(rows.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tokens.foregroundSecondary.color.opacity(0.12))
                        )
                    Spacer()
                    Text("\(formatCurrency(sectionTotal))/mo")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if rows.isEmpty {
                    Text("Nothing here yet.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { r in
                            recurringRow(r, tokens: tokens, showActions: showActions)
                            if r.id != rows.last?.id {
                                Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                            }
                        }
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

    private func recurringRow(_ r: DetectedRecurring, tokens: TokenSet, showActions: Bool) -> some View {
        let status = viewModel.status(for: r)
        let catColor = categoryColor(r.category)
        return HStack(alignment: .center, spacing: 14) {
            MerchantLogoView(
                merchant: r.merchant,
                fallbackColor: catColor,
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.merchant)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(cadenceLabel(r.cadenceDays).uppercased())
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
                Text("Next \(formatDateLong(r.predictedNext)) · last \(formatDateLong(r.lastSeen)) · \(r.occurrenceCount) seen")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(r.medianAmount))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
                Text("\(formatCurrency(monthlyEquivalent(r)))/mo")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            if showActions {
                actionButtons(for: r, status: status, tokens: tokens)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func actionButtons(for r: DetectedRecurring, status: RecurringStatus, tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            actionButton(
                label: status == .confirmed ? "Confirmed" : "Confirm",
                tint: Color(red: 0.34, green: 0.78, blue: 0.50),
                isActive: status == .confirmed
            ) {
                let next: RecurringStatus = status == .confirmed ? .detected : .confirmed
                viewModel.setStatus(next, for: r)
            }
            actionButton(
                label: status == .ignored ? "Ignored" : "Ignore",
                tint: Color(red: 0.94, green: 0.33, blue: 0.56),
                isActive: status == .ignored
            ) {
                let next: RecurringStatus = status == .ignored ? .detected : .ignored
                viewModel.setStatus(next, for: r)
            }
        }
    }

    private func actionButton(
        label: String,
        tint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(isActive ? Color.white : tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? tint : tint.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private func emptyState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No recurrings detected yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Synapse looks for charges with a stable cadence (weekly / monthly / etc) and stable amount. Connect an account or wait for more history to accumulate.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func monthlyEquivalent(_ r: DetectedRecurring) -> Decimal {
        // 30/cadence × median, in absolute units.
        let factor = Decimal(30) / Decimal(max(r.cadenceDays, 1))
        return r.medianAmount * factor
    }

    private func cadenceLabel(_ days: Int) -> String {
        switch days {
        case 7:   return "Weekly"
        case 14:  return "Bi-weekly"
        case 30:  return "Monthly"
        case 90:  return "Quarterly"
        case 365: return "Yearly"
        default:  return "\(days)d"
        }
    }

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
        nf.maximumFractionDigits = (amount > 100) ? 0 : 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0"
    }

    private func formatCompactDollar(_ amount: Decimal) -> String {
        let d = (amount as NSDecimalNumber).doubleValue
        if d >= 1000 { return String(format: "$%.1fK", d / 1000) }
        return String(format: "$%.0f", d)
    }

    private func formatDateLong(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    private static let dayNumberFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM"
        return df
    }()

    private static let dowFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "d"
        return df
    }()
}
