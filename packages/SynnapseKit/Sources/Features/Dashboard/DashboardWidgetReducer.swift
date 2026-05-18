import Foundation
import Models

/// Pure reducers that drive the Dashboard v2 hero row.
///
/// Each reducer is a `static` function over a slice of [[DashboardEntry]] +
/// a `referenceDate` + a `Calendar`. They are deliberately separated from
/// [[DashboardViewModel]] so they can be unit-tested without instantiating
/// an `@Observable` object and so future surfaces (a watchOS complication,
/// a widget extension) can call into them without dragging the SwiftUI
/// dependency along.
///
/// The reducers consume ledger entries directly — they do not filter on
/// `reviewed`. The dashboard's *inbox* counts un-reviewed rows (which is
/// what the `UNREVIEWED` widget wants), but the cash-flow / top-category /
/// next-bill widgets describe the *ledger* the user actually lives in.
@MainActor
public enum DashboardWidgetReducer {

    // MARK: - NET THIS WEEK

    /// Net (income − expense) over the 7-day window ending at
    /// `endOfWindow` (inclusive of `endOfWindow`'s day). Returns a
    /// signed total plus the same figure for the *prior* 7 days so
    /// the widget can render the Δ in one read.
    public struct NetThisWeek: Equatable, Sendable {

        /// Signed net for the current 7-day window.
        public let current: Decimal

        /// Signed net for the immediately-preceding 7-day window.
        public let previous: Decimal

        /// 7 day-buckets, oldest first. Each value is the signed sum
        /// for that day. The sparkline reads this verbatim.
        public let sparkline: [Decimal]

        /// `current - previous`. Provided so the view never has to
        /// re-derive the figure and risk a sign mismatch against
        /// the rendered `current`.
        public var delta: Decimal { current - previous }

        public init(
            current: Decimal,
            previous: Decimal,
            sparkline: [Decimal]
        ) {
            self.current = current
            self.previous = previous
            self.sparkline = sparkline
        }
    }

    /// 7-day cash-flow window ending on the day of `referenceDate`.
    /// The window includes `referenceDate.day` and the six preceding
    /// days; the "previous" comparison window is the seven days
    /// immediately before that.
    public static func netThisWeek(
        entries: [DashboardEntry],
        referenceDate: Date,
        calendar: Calendar
    ) -> NetThisWeek {
        let today = calendar.startOfDay(for: referenceDate)
        // Window: [today - 6d, today + 1d) — 7 calendar days
        // including `today`.
        guard
            let windowStart = calendar.date(byAdding: .day, value: -6, to: today),
            let windowEnd   = calendar.date(byAdding: .day, value:  1, to: today),
            let priorStart  = calendar.date(byAdding: .day, value: -7, to: windowStart)
        else {
            return NetThisWeek(current: 0, previous: 0, sparkline: Array(repeating: 0, count: 7))
        }

        var sparkBuckets: [Date: Decimal] = [:]
        var current: Decimal = 0
        var previous: Decimal = 0
        for entry in entries {
            guard let amount = entry.transaction.amount else { continue }
            let date = entry.transaction.date
            if date >= windowStart, date < windowEnd {
                current += amount
                let day = calendar.startOfDay(for: date)
                sparkBuckets[day, default: 0] += amount
            } else if date >= priorStart, date < windowStart {
                previous += amount
            }
        }
        // Materialise sparkline buckets in chronological order so the
        // chart reads left-to-right oldest → newest.
        var sparkline: [Decimal] = []
        sparkline.reserveCapacity(7)
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today)
            else { sparkline.append(0); continue }
            sparkline.append(sparkBuckets[calendar.startOfDay(for: day)] ?? 0)
        }
        return NetThisWeek(current: current, previous: previous, sparkline: sparkline)
    }

    // MARK: - UNREVIEWED

    /// The unreviewed inbox count + the ledger total. The view picks
    /// its tone (positive accent at zero, muted under ten, active
    /// above) from `count`.
    public struct UnreviewedCount: Equatable, Sendable {
        public let count: Int
        public let total: Int
        public init(count: Int, total: Int) {
            self.count = count
            self.total = total
        }
    }

    public static func unreviewedCount(
        entries: [DashboardEntry],
        ledgerTotal: Int
    ) -> UnreviewedCount {
        let unreviewed = entries.lazy.filter { !$0.reviewed }.count
        return UnreviewedCount(count: unreviewed, total: ledgerTotal)
    }

    // MARK: - TOP CATEGORY THIS WEEK

    /// Server-string category id (e.g. "RESTAURANTS") plus the
    /// summed *expense* amount for the 7-day window. Expenses are
    /// summed as their absolute value so the figure reads as a
    /// "spend" headline rather than a signed ledger figure.
    public struct TopCategory: Equatable, Sendable {
        public let category: TransactionCategory
        public let totalAbsExpense: Decimal
        public init(category: TransactionCategory, totalAbsExpense: Decimal) {
            self.category = category
            self.totalAbsExpense = totalAbsExpense
        }
    }

    /// Top expense category over the same 7-day window as
    /// `netThisWeek`. Returns `nil` if no expenses are present in the
    /// window — the view paints a "no spend yet" empty state in that
    /// case rather than a $0.00 pill.
    public static func topCategoryThisWeek(
        entries: [DashboardEntry],
        referenceDate: Date,
        calendar: Calendar
    ) -> TopCategory? {
        let today = calendar.startOfDay(for: referenceDate)
        guard
            let windowStart = calendar.date(byAdding: .day, value: -6, to: today),
            let windowEnd   = calendar.date(byAdding: .day, value:  1, to: today)
        else { return nil }
        // `TransactionCategory` is `Hashable`, so it can key a
        // dictionary directly; we sum |amount| per category and pick
        // the biggest. Income (positive amounts) is dropped from
        // this aggregation because the surface frames the figure as
        // a *spend* total.
        var buckets: [TransactionCategory: Decimal] = [:]
        for entry in entries {
            guard let amount = entry.transaction.amount, amount < 0 else { continue }
            let date = entry.transaction.date
            guard date >= windowStart, date < windowEnd else { continue }
            buckets[entry.transaction.category, default: 0] += amount.magnitude
        }
        guard let (cat, total) = buckets.max(by: { $0.value < $1.value })
        else { return nil }
        return TopCategory(category: cat, totalAbsExpense: total)
    }

    // MARK: - NEXT BILL

    /// One upcoming recurring charge. The dashboard surface does not
    /// care which detector produced it — the integrator wires a
    /// closure that returns `[Upcoming]` already sorted by `dueDate`.
    public struct Upcoming: Equatable, Sendable, Hashable {
        public let merchant: String
        public let amount: Decimal
        public let currency: String
        public let dueDate: Date
        public init(
            merchant: String,
            amount: Decimal,
            currency: String = "USD",
            dueDate: Date
        ) {
            self.merchant = merchant
            self.amount = amount
            self.currency = currency
            self.dueDate = dueDate
        }
    }

    /// Severity of the next-bill warning. The view paints today /
    /// tomorrow in a warning tone; anything farther out reads neutral.
    public enum NextBillUrgency: Sendable, Equatable {
        case today
        case tomorrow
        case later(daysAway: Int)
    }

    public struct NextBill: Equatable, Sendable {
        public let upcoming: Upcoming
        public let urgency: NextBillUrgency
        public init(upcoming: Upcoming, urgency: NextBillUrgency) {
            self.upcoming = upcoming
            self.urgency = urgency
        }
    }

    /// Resolve the next bill from a caller-supplied list of upcoming
    /// charges. The reducer is pure — it does not reach into a
    /// detector itself, the integrator wires `RecurringDetector` or
    /// the upcoming-bills API on top of it.
    public static func nextBill(
        upcoming: [Upcoming],
        referenceDate: Date,
        calendar: Calendar
    ) -> NextBill? {
        let today = calendar.startOfDay(for: referenceDate)
        // Take the soonest due date that has not already passed.
        let future = upcoming
            .filter { calendar.startOfDay(for: $0.dueDate) >= today }
            .sorted { $0.dueDate < $1.dueDate }
        guard let first = future.first else { return nil }
        let dueDay = calendar.startOfDay(for: first.dueDate)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        let urgency: NextBillUrgency
        switch days {
        case ..<0:  urgency = .today  // defensive — already filtered
        case 0:     urgency = .today
        case 1:     urgency = .tomorrow
        default:    urgency = .later(daysAway: days)
        }
        return NextBill(upcoming: first, urgency: urgency)
    }

    // MARK: - SPENDING PULSE

    /// Inspector "Spending pulse" — today's spend vs a 7-day typical.
    /// Both values are *expense* totals (positive numbers), so the
    /// view never has to flip a sign before painting the bar.
    public struct SpendingPulse: Equatable, Sendable {
        public let today: Decimal
        public let typical: Decimal
        public init(today: Decimal, typical: Decimal) {
            self.today = today
            self.typical = typical
        }
        /// Bar fill ratio (0...1). Caps at 1 so the bar never
        /// overflows; the caption still reads the raw values so the
        /// user sees "Today: $200 · Typical: $60" even when capped.
        public var ratio: Double {
            guard typical > 0 else { return today > 0 ? 1 : 0 }
            let raw = NSDecimalNumber(decimal: today).doubleValue
                / NSDecimalNumber(decimal: typical).doubleValue
            return min(max(raw, 0), 1)
        }
    }

    public static func spendingPulse(
        entries: [DashboardEntry],
        referenceDate: Date,
        calendar: Calendar
    ) -> SpendingPulse {
        let today = calendar.startOfDay(for: referenceDate)
        guard
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
            let weekStart = calendar.date(byAdding: .day, value: -7, to: today)
        else { return SpendingPulse(today: 0, typical: 0) }

        var todaySpend: Decimal = 0
        var priorSpend: Decimal = 0
        for entry in entries {
            guard let amount = entry.transaction.amount, amount < 0 else { continue }
            let date = entry.transaction.date
            if date >= today, date < tomorrow {
                todaySpend += amount.magnitude
            } else if date >= weekStart, date < today {
                priorSpend += amount.magnitude
            }
        }
        // 7-day average expense, expressed as a positive figure.
        let typical = priorSpend / 7
        return SpendingPulse(today: todaySpend, typical: typical)
    }

    // MARK: - AI digest sentence

    /// A single AI-narrated sentence shown in the inspector. The
    /// dashboard does not own the narration — the integrator passes
    /// a closure into the view that returns this struct, usually
    /// wired to `DigestReducer`. The struct is defined here so the
    /// dashboard's snapshot tests can author one inline without
    /// instantiating the Digest module.
    public struct AINarration: Equatable, Sendable, Hashable {
        public let sentence: String
        public let cta: String?
        public init(sentence: String, cta: String? = nil) {
            self.sentence = sentence
            self.cta = cta
        }
    }
}
