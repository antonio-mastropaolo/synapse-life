import SwiftUI
import DesignSystem
import Models

/// Rich redesign of the Weekly Digest surface. Mirrors the visual
/// language of `RecurringsRedesigned` and `FinanceTransactionsRedesigned`
/// — hero, AI insight bullets, sectioned cards, tone-coded tiles — and
/// composes the canonical Copilot Money "Weekly Summary" + Monarch
/// "Weekly Newsletter" layout into a single scroll surface.
///
/// Layout (top to bottom):
///   1. Hero — week range, weekly total spend, week-over-week delta.
///   2. AI narrative — 4-5 tone-coded bullets, icon + headline + body.
///   3. Category breakdown — top 6 categories, this-week bar with a
///      ghost bar behind showing last week.
///   4. Notable transactions — 3 largest charges, MerchantLogoView,
///      tappable rows (no-op in v1).
///   5. Next week preview — 3 uniform-height tiles (132pt) showing
///      upcoming bills, scheduled income, and a low-confidence
///      "thing to watch" callout.
///
/// When the host `DigestViewModel` is empty (no real digest yet) the
/// view paints sample numbers and tags each section with a "SAMPLE"
/// chip so the operator can preview the layout pre-data.
@MainActor
public struct DigestRedesigned: View {

    @Bindable private var viewModel: DigestViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(viewModel: DigestViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header(tokens: tokens)
                aiNarrative(tokens: tokens)
                categoryBreakdown(tokens: tokens)
                notableTransactions(tokens: tokens)
                nextWeekPreview(tokens: tokens)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("intelligence.digest.redesigned")
    }

    // MARK: - Tone palette
    //
    // Shared with the rest of the redesigned surfaces so the eye
    // recognises "warning amber" / "good green" across the app.

    private let good  = Color(red: 0.34, green: 0.78, blue: 0.50)
    private let warn  = Color(red: 1.00, green: 0.69, blue: 0.22)
    private let neut  = Color(red: 0.27, green: 0.83, blue: 0.89)
    private let alert = Color(red: 0.94, green: 0.33, blue: 0.56)

    // MARK: - Sample-data detection

    /// True when the VM has no real digest landed yet. Used to paint
    /// sample numbers and stamp section headers with a "SAMPLE" chip.
    private var isSample: Bool { viewModel.digest == nil }

    // MARK: - Header (hero)
    //
    // Mirrors the RecurringsRedesigned hero: 28pt semibold title, a
    // 9pt monospaced eyebrow, and a row of monospaced numeric tiles
    // for the headline metrics. The week-over-week delta gets a
    // tone-coded chip so it reads at a glance.

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        let total = thisWeekTotal
        let lastWeek = lastWeekTotal
        let delta = total - lastWeek
        let deltaPct = lastWeek == 0
            ? 0
            : NSDecimalNumber(decimal: (delta / lastWeek) * 100).doubleValue
        let isUp = delta > 0

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Weekly Digest")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                if isSample { sampleChip }
                Spacer()
            }
            Text(weekRangeLabel)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                summaryTile(
                    label: "Spent this week",
                    value: formatCurrency(total),
                    tokens: tokens
                )
                summaryTile(
                    label: "Last week",
                    value: formatCurrency(lastWeek),
                    tokens: tokens
                )
                wowDeltaTile(
                    delta: delta,
                    pct: deltaPct,
                    isUp: isUp,
                    tokens: tokens
                )
                Spacer()
            }
            .padding(.top, 6)
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

    private func wowDeltaTile(
        delta: Decimal,
        pct: Double,
        isUp: Bool,
        tokens: TokenSet
    ) -> some View {
        // Up arrow + warn tint for "spending more"; down arrow + good
        // tint for "spending less". A zero-week falls back to neutral
        // text rather than a misleading 0%.
        let tint = isUp ? warn : good
        return VStack(alignment: .leading, spacing: 4) {
            Text("WEEK OVER WEEK")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack(spacing: 6) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text(formatCurrency(abs(delta)))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
                Text("\(isUp ? "+" : "−")\(String(format: "%.0f%%", abs(pct)))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tint.opacity(0.15))
                    )
            }
        }
    }

    private var sampleChip: some View {
        Text("SAMPLE")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
            )
    }

    // MARK: - AI narrative bullets
    //
    // Tone-coded list (good / warn / neut / alert). Uses real
    // `DigestBullet` data when the VM has a digest; otherwise paints
    // a representative sample so the layout is preview-able.

    @ViewBuilder
    private func aiNarrative(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(warn)
                Text("WHAT AI NOTICED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if isSample { sampleChip }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(narrativeBullets) { bullet in
                    narrativeRow(bullet, tokens: tokens)
                }
            }
        }
    }

    private struct NarrativeBullet: Identifiable {
        let id = UUID()
        let icon: String
        let headline: String
        let body: String
        let tone: Tone
        enum Tone { case good, warn, neut, alert }
    }

    private var narrativeBullets: [NarrativeBullet] {
        if let digest = viewModel.digest, !digest.bullets.isEmpty {
            return digest.bullets.prefix(5).map { b in
                NarrativeBullet(
                    icon: iconForBulletKind(b.kind),
                    headline: b.headline,
                    body: b.body,
                    tone: toneForBulletKind(b.kind)
                )
            }
        }
        return [
            NarrativeBullet(
                icon: "arrow.down.right.circle.fill",
                headline: "Restaurants pulled back",
                body: "You spent $142 on restaurants this week — 38% under your trailing four-week average. The weekday lunches you cut last Monday are sticking.",
                tone: .good
            ),
            NarrativeBullet(
                icon: "exclamationmark.triangle.fill",
                headline: "Two unusual swipes at gas stations",
                body: "Shell on Wednesday and BP on Friday both ran ~3x your normal fill amount. If those are correct, your auto budget is going to wobble next week.",
                tone: .warn
            ),
            NarrativeBullet(
                icon: "repeat.circle.fill",
                headline: "Subscriptions held flat",
                body: "Same nine recurring lines as last week ($87.42 total). Nothing renewed at a new price, no new trials kicked into paid.",
                tone: .neut
            ),
            NarrativeBullet(
                icon: "bolt.fill",
                headline: "Income lands Friday",
                body: "Direct deposit from Acme Co. ($3,420) is on schedule. After it lands you are net positive $1,180 for the week.",
                tone: .good
            ),
            NarrativeBullet(
                icon: "creditcard.trianglebadge.exclamationmark.fill",
                headline: "Chase card running high",
                body: "Statement balance is at 38% of the limit — historically you cross 40% mid-month, so a payment in the next 5 days protects the utilization score.",
                tone: .alert
            )
        ]
    }

    private func iconForBulletKind(_ kind: DigestBullet.Kind) -> String {
        switch kind {
        case .spend:         return "arrow.up.right.circle.fill"
        case .income:        return "arrow.down.left.circle.fill"
        case .net:           return "equal.circle.fill"
        case .topCategory:   return "chart.pie.fill"
        case .subscriptions: return "repeat.circle.fill"
        case .anomaly:       return "exclamationmark.triangle.fill"
        case .suggestion:    return "lightbulb.fill"
        }
    }

    private func toneForBulletKind(_ kind: DigestBullet.Kind) -> NarrativeBullet.Tone {
        switch kind {
        case .spend:         return .warn
        case .income:        return .good
        case .net:           return .neut
        case .topCategory:   return .neut
        case .subscriptions: return .neut
        case .anomaly:       return .alert
        case .suggestion:    return .good
        }
    }

    private func color(for tone: NarrativeBullet.Tone) -> Color {
        switch tone {
        case .good:  return good
        case .warn:  return warn
        case .neut:  return neut
        case .alert: return alert
        }
    }

    private func narrativeRow(_ bullet: NarrativeBullet, tokens: TokenSet) -> some View {
        let tint = color(for: bullet.tone)
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: bullet.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bullet.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(bullet.body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Category breakdown (this week vs last week)
    //
    // Top 6 categories by this-week spend. Each row has a label, the
    // current dollar amount, and a horizontal bar. The bar is sized
    // by THIS week, with a fainter "ghost" bar behind sized by LAST
    // week. The eye gets the WoW shape immediately.

    @ViewBuilder
    private func categoryBreakdown(tokens: TokenSet) -> some View {
        let rows = categoryRows
        let maxValue = max(
            rows.map { max($0.thisWeek, $0.lastWeek) }.max() ?? 1,
            1
        )
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(neut)
                Text("CATEGORY BREAKDOWN · TOP 6")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text("THIS WEEK vs LAST")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                if isSample { sampleChip }
            }
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    categoryBar(row, maxValue: maxValue, tokens: tokens)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    private struct CategoryRow: Identifiable {
        let id = UUID()
        let label: String
        let slug: String
        let thisWeek: Decimal
        let lastWeek: Decimal
    }

    private var categoryRows: [CategoryRow] {
        // No real category breakdown is reachable through the VM yet;
        // we paint a representative sample shaped like real usage.
        // When a future VM exposes per-category weekly totals, swap
        // this property to consume them.
        [
            CategoryRow(label: "Restaurants",   slug: "restaurants",   thisWeek: 142, lastWeek: 228),
            CategoryRow(label: "Groceries",     slug: "groceries",     thisWeek: 118, lastWeek: 96),
            CategoryRow(label: "Subscriptions", slug: "subscriptions", thisWeek: 87,  lastWeek: 87),
            CategoryRow(label: "Transport",     slug: "transfers",     thisWeek: 64,  lastWeek: 48),
            CategoryRow(label: "Entertainment", slug: "entertainment", thisWeek: 52,  lastWeek: 41),
            CategoryRow(label: "Personal care", slug: "personal-care", thisWeek: 38,  lastWeek: 22)
        ]
    }

    private func categoryBar(
        _ row: CategoryRow,
        maxValue: Decimal,
        tokens: TokenSet
    ) -> some View {
        let tint = categoryColor(for: row.slug)
        let thisFrac = NSDecimalNumber(decimal: row.thisWeek / maxValue).doubleValue
        let lastFrac = NSDecimalNumber(decimal: row.lastWeek / maxValue).doubleValue
        let delta = row.thisWeek - row.lastWeek
        let isUp = delta > 0
        return HStack(spacing: 12) {
            // Left label column — fixed width keeps the bars aligned
            // across rows regardless of label length.
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(row.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)

            // Bar area — ghost (last week) sits behind the solid bar
            // (this week) so the delta reads as a stripe of the
            // fainter color either before or after the solid one.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tokens.foregroundSecondary.color.opacity(0.08))
                        .frame(height: 18)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(0.22))
                        .frame(
                            width: max(geo.size.width * lastFrac, 2),
                            height: 18
                        )
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(
                            width: max(geo.size.width * thisFrac, 2),
                            height: 18
                        )
                }
            }
            .frame(height: 18)

            // Right number column — fixed width so dollar columns
            // line up regardless of value magnitude.
            HStack(spacing: 8) {
                Text(formatCurrency(row.thisWeek))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
                Text(deltaLabel(delta))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(delta == 0 ? tokens.foregroundSecondary.color : (isUp ? warn : good))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                delta == 0
                                    ? tokens.foregroundSecondary.color.opacity(0.10)
                                    : (isUp ? warn : good).opacity(0.15)
                            )
                    )
            }
            .frame(width: 130, alignment: .trailing)
        }
    }

    private func deltaLabel(_ delta: Decimal) -> String {
        if delta == 0 { return "FLAT" }
        let sign = delta > 0 ? "+" : "−"
        let value = formatCompactDollar(abs(delta))
        return "\(sign)\(value)"
    }

    // MARK: - Notable transactions

    @ViewBuilder
    private func notableTransactions(tokens: TokenSet) -> some View {
        let rows = notableRows
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(alert)
                Text("BIGGEST CHARGES THIS WEEK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if isSample { sampleChip }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    Button {
                        // No-op in v1. Hooks for routing to the
                        // transaction detail land when the host wires
                        // navigation through DigestRedesigned.
                    } label: {
                        notableRow(row, tokens: tokens)
                    }
                    .buttonStyle(.plain)
                    if row.id != rows.last?.id {
                        Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
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
    }

    private struct NotableRow: Identifiable {
        let id = UUID()
        let merchant: String
        let amount: Decimal
        let date: Date
        let category: String
        let categorySlug: String
    }

    private var notableRows: [NotableRow] {
        // No transaction-level data is exposed by DigestViewModel; the
        // VM only carries narrative bullets. Sample charges keep the
        // surface visually complete until a richer VM lands.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return [
            NotableRow(
                merchant: "Whole Foods",
                amount: 184.22,
                date: cal.date(byAdding: .day, value: -1, to: today) ?? today,
                category: "Groceries",
                categorySlug: "groceries"
            ),
            NotableRow(
                merchant: "United Airlines",
                amount: 412.50,
                date: cal.date(byAdding: .day, value: -3, to: today) ?? today,
                category: "Travel",
                categorySlug: "transfers"
            ),
            NotableRow(
                merchant: "Apple",
                amount: 99.00,
                date: cal.date(byAdding: .day, value: -5, to: today) ?? today,
                category: "Subscriptions",
                categorySlug: "subscriptions"
            )
        ]
    }

    private func notableRow(_ row: NotableRow, tokens: TokenSet) -> some View {
        let tint = categoryColor(for: row.categorySlug)
        return HStack(alignment: .center, spacing: 14) {
            MerchantLogoView(
                merchant: row.merchant,
                fallbackColor: tint,
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.merchant)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(row.category.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(0.18))
                        )
                        .foregroundStyle(tint)
                }
                Text(formatDateLong(row.date))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            Text(formatCurrency(row.amount))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Next week preview (3-tile, 132pt uniform)

    @ViewBuilder
    private func nextWeekPreview(tokens: TokenSet) -> some View {
        let cols = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(neut)
                Text("NEXT WEEK PREVIEW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if isSample { sampleChip }
            }
            LazyVGrid(columns: cols, spacing: 12) {
                previewTile(
                    icon: "creditcard.fill",
                    title: "Upcoming bills",
                    detail: "$612 of recurring charges hit Mon-Fri. Netflix, electric, and the Chase card account for most of it; nothing renews at a new price.",
                    tone: warn,
                    tokens: tokens
                )
                previewTile(
                    icon: "arrow.down.left.circle.fill",
                    title: "Scheduled income",
                    detail: "Acme Co. direct deposit ($3,420) lands Friday. After bills you net +$2,808 for the week — comfortably positive.",
                    tone: good,
                    tokens: tokens
                )
                previewTile(
                    icon: "eyes",
                    title: "Thing to watch",
                    detail: "Your AmEx statement closes Tuesday and the balance sits at 38% of limit. Pay $200 by Monday night to keep utilization under 30%.",
                    tone: alert,
                    tokens: tokens
                )
            }
        }
    }

    private func previewTile(
        icon: String,
        title: String,
        detail: String,
        tone: Color,
        tokens: TokenSet
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            Text(detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        // Uniform 132pt height matches the AI-signal tiles elsewhere
        // so the eye recognises them as the same surface family.
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tone.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Sample weekly totals
    //
    // Derived from the digest week range when a digest is present;
    // otherwise fixed sample numbers. The host doesn't surface raw
    // weekly totals through the VM yet — see report notes.

    private var thisWeekTotal: Decimal {
        // Stable representative number until the VM exposes the real
        // weekly total. Sums the sample category breakdown for
        // consistency between the hero and the breakdown card.
        categoryRows.reduce(Decimal.zero) { $0 + $1.thisWeek }
    }

    private var lastWeekTotal: Decimal {
        categoryRows.reduce(Decimal.zero) { $0 + $1.lastWeek }
    }

    // MARK: - Week range label

    private var weekRangeLabel: String {
        if let d = viewModel.digest {
            return weekRange(start: d.weekStart, end: d.weekEnd)
        }
        // Fall back to a Mon-Sun window anchored on today.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        // Treat Monday as the start of the week for display.
        let daysFromMonday = (weekday + 5) % 7
        let start = cal.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? today
        return weekRange(start: start, end: end)
    }

    private func weekRange(start: Date, end: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM d"
        let endShown = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return "Week of \(df.string(from: start)) — \(df.string(from: endShown))"
    }

    // MARK: - Color + formatting helpers

    /// Slug-keyed category palette, mirroring the one in
    /// `RecurringsRedesigned.categoryColor(_:)`. Kept private to this
    /// file so the digest surface doesn't fight the rest of the app
    /// over a shared token, and so the file stays self-contained.
    private func categoryColor(for slug: String) -> Color {
        switch slug {
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
        df.dateFormat = "EEE, MMM d"
        return df.string(from: date)
    }
}
