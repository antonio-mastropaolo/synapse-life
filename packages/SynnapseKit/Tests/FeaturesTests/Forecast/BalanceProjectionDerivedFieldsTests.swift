import Foundation
import Testing
@testable import Models
@testable import Features

private let fixedToday: Date = {
    var c = DateComponents()
    c.calendar = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")
    c.year = 2026; c.month = 5; c.day = 17
    c.hour = 12; c.minute = 0
    return c.date!
}()

private func startOfDay(_ d: Date) -> Date {
    // Mirror BalanceProjector's calendar — default (local) gregorian.
    Calendar(identifier: .gregorian).startOfDay(for: d)
}

private func dayOffset(_ days: Int) -> Date {
    startOfDay(fixedToday).addingTimeInterval(Double(days) * 86_400)
}

private func checking(balance: Decimal) -> FinanceAccount {
    FinanceAccount(
        id: "acct-c", institutionId: "inst", institutionName: "Bank",
        name: "Checking", officialName: nil, mask: "1234",
        kind: .checking, currency: "USD",
        currentBalance: balance, availableBalance: balance,
        limitAmount: nil, balanceCapturedAt: nil
    )
}

private func recurring(
    merchant: String,
    amount: Decimal,
    cadenceDays: Int = 30,
    nextInDays: Int,
    category: CategoryID = .subscriptions
) -> DetectedRecurring {
    let next = fixedToday.addingTimeInterval(Double(nextInDays) * 86_400)
    return DetectedRecurring(
        merchant: merchant,
        category: category,
        medianAmount: amount,
        cadenceDays: cadenceDays,
        lastSeen: fixedToday.addingTimeInterval(-Double(cadenceDays - nextInDays) * 86_400),
        predictedNext: next,
        occurrenceCount: 6,
        confidence: 0.95,
        transactionIds: []
    )
}

/// Tests the derived KPI fields that the Forecast v2 surface agents
/// (B/C/D/E) read off the [[BalanceProjection]]. Every field is a pure
/// function of the same inputs the existing tests already cover, so
/// these cases pin the exact contract instead of re-deriving the
/// projection from scratch.
@Suite("BalanceProjection derived KPI fields")
struct BalanceProjectionDerivedFieldsTests {

    @Test("lowestProjectedBalance + date track the minimum of the running balance")
    func lowestPoint() {
        // Start 1,000. Day 5 -300 → 700. Day 12 -500 → 200. Day 20
        // +400 → 600. Day 25 -50 → 550.
        let p = BalanceProjector.project(
            accounts: [checking(balance: 1_000)],
            recurrings: [
                recurring(merchant: "Rent", amount: 300, cadenceDays: 90, nextInDays: 5, category: .other),
                recurring(merchant: "Insurance", amount: 500, cadenceDays: 90, nextInDays: 12, category: .other),
                recurring(merchant: "Spotify", amount: 50, cadenceDays: 90, nextInDays: 25)
            ],
            incomeRecurrings: [
                recurring(merchant: "Side gig", amount: 400, cadenceDays: 90, nextInDays: 20, category: .income)
            ],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.lowestProjectedBalance == Decimal(200))
        // Lowest occurs at day 12 and persists through day 19 — the
        // contract is to return the FIRST date the minimum is reached.
        #expect(p.lowestProjectedBalanceDate == dayOffset(12))
    }

    @Test("runwayDays is the day count from today to projectedZeroDate")
    func runwayDaysWhenZeroCrosses() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 200)],
            recurrings: [
                recurring(merchant: "Rent", amount: 1_850, cadenceDays: 90, nextInDays: 5, category: .other)
            ],
            incomeRecurrings: [],
            horizonDays: 30,
            today: fixedToday
        )
        // projectedZeroDate carries the original flow timestamp (the
        // recurring's `predictedNext`), not the start-of-day key —
        // runwayDays is computed by start-of-day diff so it's the
        // calendar-day delta regardless.
        #expect(p.projectedZeroDate == fixedToday.addingTimeInterval(5 * 86_400))
        #expect(p.runwayDays == 5)
    }

    @Test("runwayDays is nil when the balance never crosses zero")
    func runwayDaysNilWhenSafe() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 5_000)],
            recurrings: [
                recurring(merchant: "Spotify", amount: 17, cadenceDays: 30, nextInDays: 3)
            ],
            incomeRecurrings: [],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.projectedZeroDate == nil)
        #expect(p.runwayDays == nil)
    }

    @Test("freeCashAtHorizon equals the last point of the daily series")
    func freeCashEndOfHorizon() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 1_000)],
            recurrings: [
                recurring(merchant: "Rent", amount: 200, cadenceDays: 90, nextInDays: 10, category: .other)
            ],
            incomeRecurrings: [
                recurring(merchant: "Payroll", amount: 500, cadenceDays: 90, nextInDays: 20, category: .income)
            ],
            horizonDays: 30,
            today: fixedToday
        )
        // 1,000 - 200 + 500 = 1,300 at horizon.
        #expect(p.freeCashAtHorizon == Decimal(1_300))
        #expect(p.dailyBalanceSeries.last?.amount == p.freeCashAtHorizon)
    }

    @Test("biggestSingleCharge picks the largest scheduled debit")
    func biggestCharge() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 5_000)],
            recurrings: [
                recurring(merchant: "Netflix", amount: 23, cadenceDays: 30, nextInDays: 3),
                recurring(merchant: "Rent", amount: 1_850, cadenceDays: 30, nextInDays: 7, category: .other),
                recurring(merchant: "Spotify", amount: 17, cadenceDays: 30, nextInDays: 10)
            ],
            incomeRecurrings: [],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.biggestSingleCharge?.merchant == "Rent")
        #expect(p.biggestSingleCharge?.amount == Decimal(1_850))
    }

    @Test("biggestSingleCharge is nil when there are no debits")
    func biggestChargeEmpty() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 1_000)],
            recurrings: [],
            incomeRecurrings: [],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.biggestSingleCharge == nil)
    }

    @Test("coverageRatio is credits / debits, nil when debits are zero")
    func coverageRatio() {
        // 3,000 credits / 1,000 debits = 3.0
        let p = BalanceProjector.project(
            accounts: [checking(balance: 500)],
            recurrings: [
                recurring(merchant: "Rent", amount: 1_000, cadenceDays: 90, nextInDays: 5, category: .other)
            ],
            incomeRecurrings: [
                recurring(merchant: "Payroll", amount: 3_000, cadenceDays: 90, nextInDays: 10, category: .income)
            ],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.coverageRatio == Decimal(3))

        let noDebits = BalanceProjector.project(
            accounts: [checking(balance: 500)],
            recurrings: [],
            incomeRecurrings: [
                recurring(merchant: "Payroll", amount: 3_000, cadenceDays: 90, nextInDays: 10, category: .income)
            ],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(noDebits.coverageRatio == nil)
    }
}
