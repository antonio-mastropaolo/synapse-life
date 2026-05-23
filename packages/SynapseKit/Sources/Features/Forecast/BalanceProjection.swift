import Foundation
import Models
import SynapseCharts

/// One scheduled flow in the projection window — a recurring bill or
/// recurring deposit predicted to hit on a specific day. We carry the
/// merchant + amount so the UI can render the "Poshmark · May 17 ·
/// $10.00" row directly off the projection.
public struct ScheduledFlow: Sendable, Hashable, Identifiable {
    public var id: String { "flow.\(merchant.lowercased().replacingOccurrences(of: " ", with: "-")).\(Int(date.timeIntervalSince1970))" }

    public enum Direction: Sendable, Hashable { case debit, credit }

    public let merchant: String
    public let amount: Decimal     // always positive; sign carried by `direction`
    public let date: Date
    public let direction: Direction
    public let category: CategoryID

    public init(
        merchant: String,
        amount: Decimal,
        date: Date,
        direction: Direction,
        category: CategoryID
    ) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.direction = direction
        self.category = category
    }
}

/// Deterministic forward projection of the user's checking balance.
///
/// Distinct from the stochastic [[Forecast]] envelope shipped by
/// [[ForecastReducer]]: that one paints a confidence band off the
/// 30-day drift. This one answers a sharper question — "given my
/// detected recurrings, what specific bills are coming and on which
/// day does the central estimate cross zero?". The Forecast surface's
/// stat cards, the "may hit zero on May 18" banner, and the v2 chart
/// + 8-card KPI grid all read from this struct.
public struct BalanceProjection: Sendable, Hashable {
    public let startingChecking: Decimal
    public let scheduledDebits: [ScheduledFlow]
    public let scheduledCredits: [ScheduledFlow]
    public let projectedZeroDate: Date?
    public let totalDebits: Decimal
    public let totalCredits: Decimal
    public let predictedChargesCount: Int
    public let horizonDays: Int
    public let today: Date

    // MARK: - Forecast v2 derived fields
    //
    // These are populated by the same single running-balance walk that
    // resolves `projectedZeroDate`, so adding them is free at compute
    // time. The chart + KPI grid + scenario panel read off these
    // instead of re-deriving the walk per call-site.

    /// End-of-day projected checking balance for every day in
    /// `[today, today + horizonDays]`. Always contains
    /// `horizonDays + 1` points (one per day inclusive); the
    /// degenerate `horizonDays == 0` case still yields a one-element
    /// anchor series so charts have something to render.
    public let dailyBalanceSeries: [MoneyTimePoint]

    /// Lowest point on `dailyBalanceSeries` — useful for the
    /// "Lowest balance" KPI card on the Forecast v2 grid.
    public let lowestProjectedBalance: Decimal

    /// Date of `lowestProjectedBalance`. When the minimum persists
    /// across multiple days (e.g. flat after a debit, before any
    /// later credit), the FIRST day it's reached wins.
    public let lowestProjectedBalanceDate: Date

    /// Calendar days from `today` to `projectedZeroDate`. `nil` when
    /// the balance never crosses zero in the horizon — surfaces should
    /// render "—" in that case rather than a dash-zero ambiguity.
    public let runwayDays: Int?

    /// Projected balance at end of horizon — equivalent to
    /// `dailyBalanceSeries.last?.amount`.
    public let freeCashAtHorizon: Decimal

    /// The single largest debit in `scheduledDebits`. `nil` when the
    /// horizon contains no debits. Ties are broken by earliest date,
    /// then merchant name (sort already establishes that order).
    public let biggestSingleCharge: ScheduledFlow?

    /// `totalCredits / totalDebits`. `nil` when `totalDebits == 0`
    /// so callers can render "∞" or "—" deliberately rather than
    /// dividing by zero.
    public let coverageRatio: Decimal?

    public init(
        startingChecking: Decimal,
        scheduledDebits: [ScheduledFlow],
        scheduledCredits: [ScheduledFlow],
        projectedZeroDate: Date?,
        totalDebits: Decimal,
        totalCredits: Decimal,
        predictedChargesCount: Int,
        horizonDays: Int,
        today: Date,
        dailyBalanceSeries: [MoneyTimePoint],
        lowestProjectedBalance: Decimal,
        lowestProjectedBalanceDate: Date,
        runwayDays: Int?,
        freeCashAtHorizon: Decimal,
        biggestSingleCharge: ScheduledFlow?,
        coverageRatio: Decimal?
    ) {
        self.startingChecking = startingChecking
        self.scheduledDebits = scheduledDebits
        self.scheduledCredits = scheduledCredits
        self.projectedZeroDate = projectedZeroDate
        self.totalDebits = totalDebits
        self.totalCredits = totalCredits
        self.predictedChargesCount = predictedChargesCount
        self.horizonDays = horizonDays
        self.today = today
        self.dailyBalanceSeries = dailyBalanceSeries
        self.lowestProjectedBalance = lowestProjectedBalance
        self.lowestProjectedBalanceDate = lowestProjectedBalanceDate
        self.runwayDays = runwayDays
        self.freeCashAtHorizon = freeCashAtHorizon
        self.biggestSingleCharge = biggestSingleCharge
        self.coverageRatio = coverageRatio
    }
}

/// Pure-logic balance projection.
public enum BalanceProjector {

    /// Output of a single day-by-day walk over the merged flow list.
    /// Sharing this between the existing `projectedZeroDate` resolution
    /// and the new daily-series field means the projection is a single
    /// O(flows + horizonDays) pass — chart, KPIs, and zero-crossing
    /// all derive from the same numbers.
    struct WalkResult {
        let dailySeries: [MoneyTimePoint]
        let zeroCrossing: Date?
        let lowestBalance: Decimal
        let lowestBalanceDate: Date
    }

    /// Project the sum of checking/depository account balances forward
    /// `horizonDays` days using the supplied detected recurring debits
    /// and credits. Each recurring's `predictedNext` is rolled forward
    /// at `cadenceDays` until it leaves the horizon, so a monthly bill
    /// hits once and a weekly bill hits ~4 times in a 30-day window.
    ///
    /// - Parameters:
    ///   - accounts: full account list; only checking-style accounts
    ///     contribute to `startingChecking`. Savings, credit, and
    ///     brokerage are deliberately excluded — the projection is
    ///     about runway, not net worth.
    ///   - recurrings: detected recurring debits.
    ///   - incomeRecurrings: detected recurring credits.
    ///   - horizonDays: defaults to 30 to match the Forecast surface.
    ///   - today: injected for tests.
    public static func project(
        accounts: [FinanceAccount],
        recurrings: [DetectedRecurring],
        incomeRecurrings: [DetectedRecurring],
        horizonDays: Int = 30,
        today: Date = Date()
    ) -> BalanceProjection {

        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: today)
        // Horizon end is INCLUSIVE for the daily series (we want the
        // last-day point) but EXCLUSIVE for flow expansion (a recurring
        // landing exactly on horizonEnd belongs to the next window).
        // Carry both: expansion uses `horizonEndExclusive`, the walk
        // sweeps `0...horizonDays` inclusive for the series.
        let horizonEndExclusive = startOfToday.addingTimeInterval(Double(horizonDays) * 86_400)

        let startingChecking = accounts
            .filter { isCheckingLike($0.kind) }
            .compactMap { $0.currentBalance }
            .reduce(Decimal.zero, +)

        let scheduledDebits = expand(
            recurrings: recurrings,
            direction: .debit,
            startOfToday: startOfToday,
            horizonEnd: horizonEndExclusive
        )
        let scheduledCredits = expand(
            recurrings: incomeRecurrings,
            direction: .credit,
            startOfToday: startOfToday,
            horizonEnd: horizonEndExclusive
        )

        let totalDebits = scheduledDebits.reduce(Decimal.zero) { $0 + $1.amount }
        let totalCredits = scheduledCredits.reduce(Decimal.zero) { $0 + $1.amount }

        let walk = runningBalanceWalk(
            startingChecking: startingChecking,
            debits: scheduledDebits,
            credits: scheduledCredits,
            startOfToday: startOfToday,
            horizonDays: horizonDays,
            calendar: cal
        )

        let runwayDays: Int? = walk.zeroCrossing.flatMap { zeroDate in
            let zeroStart = cal.startOfDay(for: zeroDate)
            return cal.dateComponents([.day], from: startOfToday, to: zeroStart).day
        }

        let biggest = scheduledDebits.max(by: { $0.amount < $1.amount })

        let coverage: Decimal? = totalDebits == 0
            ? nil
            : totalCredits / totalDebits

        return BalanceProjection(
            startingChecking: startingChecking,
            scheduledDebits: scheduledDebits,
            scheduledCredits: scheduledCredits,
            projectedZeroDate: walk.zeroCrossing,
            totalDebits: totalDebits,
            totalCredits: totalCredits,
            predictedChargesCount: scheduledDebits.count,
            horizonDays: horizonDays,
            today: today,
            dailyBalanceSeries: walk.dailySeries,
            lowestProjectedBalance: walk.lowestBalance,
            lowestProjectedBalanceDate: walk.lowestBalanceDate,
            runwayDays: runwayDays,
            freeCashAtHorizon: walk.dailySeries.last?.amount ?? startingChecking,
            biggestSingleCharge: biggest,
            coverageRatio: coverage
        )
    }

    // MARK: - Helpers

    static func isCheckingLike(_ kind: AccountKind) -> Bool {
        switch kind {
        case .checking: return true
        // Treat .other and PayPal-style cash buckets as checking-like
        // because the user can pay bills out of them.
        case .other:    return true
        default:        return false
        }
    }

    /// Single source of truth for the day-by-day balance walk. Builds
    /// the per-day series, the zero-crossing date, and the lowest-point
    /// pair in one pass. Credits are applied before debits when they
    /// share a day so a payday landing alongside rent doesn't paint a
    /// false zero crossing.
    static func runningBalanceWalk(
        startingChecking: Decimal,
        debits: [ScheduledFlow],
        credits: [ScheduledFlow],
        startOfToday: Date,
        horizonDays: Int,
        calendar: Calendar
    ) -> WalkResult {
        // Group flows by their start-of-day key so the walk can apply
        // every flow that lands on a given day in one step.
        var flowsByDay: [Date: [ScheduledFlow]] = [:]
        for flow in debits + credits {
            let key = calendar.startOfDay(for: flow.date)
            flowsByDay[key, default: []].append(flow)
        }
        for key in flowsByDay.keys {
            // Credits first on the same day — same rule as the
            // pre-v2 merged sort.
            flowsByDay[key]?.sort { lhs, rhs in
                if lhs.direction == rhs.direction {
                    return lhs.merchant < rhs.merchant
                }
                return lhs.direction == .credit && rhs.direction == .debit
            }
        }

        var running = startingChecking
        var lowest = startingChecking
        var lowestDate = startOfToday
        var zero: Date?
        var series: [MoneyTimePoint] = []
        series.reserveCapacity(horizonDays + 1)

        // Walk inclusively from day 0 (today) through day horizonDays.
        // For horizonDays == 0 we still emit a single anchor point so
        // chart consumers don't have to special-case empty input.
        for dayOffset in 0...max(0, horizonDays) {
            let day = startOfToday.addingTimeInterval(Double(dayOffset) * 86_400)
            // Day 0 carries no flows applied yet — the anchor point is
            // the literal starting balance, mirroring the pre-v2
            // semantics. From day 1 onward, apply every flow that
            // lands on this calendar day before snapshotting.
            if dayOffset > 0, let dayFlows = flowsByDay[day] {
                for flow in dayFlows {
                    switch flow.direction {
                    case .debit:  running -= flow.amount
                    case .credit: running += flow.amount
                    }
                    if zero == nil, running <= 0 {
                        zero = flow.date
                    }
                }
            }
            series.append(MoneyTimePoint(date: day, amount: running))
            if running < lowest {
                lowest = running
                lowestDate = day
            }
        }

        return WalkResult(
            dailySeries: series,
            zeroCrossing: zero,
            lowestBalance: lowest,
            lowestBalanceDate: lowestDate
        )
    }

    static func expand(
        recurrings: [DetectedRecurring],
        direction: ScheduledFlow.Direction,
        startOfToday: Date,
        horizonEnd: Date
    ) -> [ScheduledFlow] {
        var out: [ScheduledFlow] = []
        for r in recurrings {
            // Roll the predicted-next forward at cadenceDays until it
            // either lands in or past the horizon. Skip dates that
            // landed in the past (e.g. a detection's predicted-next
            // was yesterday because the user is reading the projection
            // late).
            var date = r.predictedNext
            let cadence = Double(r.cadenceDays) * 86_400
            // If the prediction is in the past, fast-forward it
            // ceiling-wise to today.
            while date < startOfToday {
                date = date.addingTimeInterval(cadence)
            }
            while date < horizonEnd {
                out.append(ScheduledFlow(
                    merchant: r.merchant,
                    amount: r.medianAmount,
                    date: date,
                    direction: direction,
                    category: r.category
                ))
                date = date.addingTimeInterval(cadence)
            }
        }
        return out.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.merchant < rhs.merchant }
            return lhs.date < rhs.date
        }
    }
}
