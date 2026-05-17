import Foundation
import Models

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
/// stat cards and the "may hit zero on May 18" banner all read from
/// this struct.
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

    public init(
        startingChecking: Decimal,
        scheduledDebits: [ScheduledFlow],
        scheduledCredits: [ScheduledFlow],
        projectedZeroDate: Date?,
        totalDebits: Decimal,
        totalCredits: Decimal,
        predictedChargesCount: Int,
        horizonDays: Int,
        today: Date
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
    }
}

/// Pure-logic balance projection.
public enum BalanceProjector {

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
        let horizonEnd = startOfToday.addingTimeInterval(Double(horizonDays) * 86_400)

        let startingChecking = accounts
            .filter { isCheckingLike($0.kind) }
            .compactMap { $0.currentBalance }
            .reduce(Decimal.zero, +)

        let scheduledDebits = expand(
            recurrings: recurrings,
            direction: .debit,
            startOfToday: startOfToday,
            horizonEnd: horizonEnd
        )
        let scheduledCredits = expand(
            recurrings: incomeRecurrings,
            direction: .credit,
            startOfToday: startOfToday,
            horizonEnd: horizonEnd
        )

        let totalDebits = scheduledDebits.reduce(Decimal.zero) { $0 + $1.amount }
        let totalCredits = scheduledCredits.reduce(Decimal.zero) { $0 + $1.amount }

        // Step through the horizon day-by-day applying flows in date
        // order. First day the running balance hits ≤ 0 wins.
        let merged: [ScheduledFlow] = (scheduledDebits + scheduledCredits)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    // Credits before debits on the same day so a
                    // payday doesn't get a false "zero crossing" if
                    // both land together.
                    return lhs.direction == .credit && rhs.direction == .debit
                }
                return lhs.date < rhs.date
            }
        var running = startingChecking
        var zero: Date?
        for flow in merged {
            switch flow.direction {
            case .debit:  running -= flow.amount
            case .credit: running += flow.amount
            }
            if zero == nil, running <= 0 {
                zero = flow.date
            }
        }

        return BalanceProjection(
            startingChecking: startingChecking,
            scheduledDebits: scheduledDebits,
            scheduledCredits: scheduledCredits,
            projectedZeroDate: zero,
            totalDebits: totalDebits,
            totalCredits: totalCredits,
            predictedChargesCount: scheduledDebits.count,
            horizonDays: horizonDays,
            today: today
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
