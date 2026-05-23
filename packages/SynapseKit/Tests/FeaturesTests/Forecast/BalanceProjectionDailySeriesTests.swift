import Foundation
import Testing
@testable import Models
@testable import Features

/// Fixed reference today, mirrors the anchor used by
/// [[BalanceProjectionTests]] so cross-test reasoning lines up.
private let fixedToday: Date = {
    var c = DateComponents()
    c.calendar = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")
    c.year = 2026; c.month = 5; c.day = 17
    c.hour = 12; c.minute = 0
    return c.date!
}()

private func startOfDay(_ d: Date) -> Date {
    // Mirror BalanceProjector's calendar — the projector uses the
    // default (local) calendar's startOfDay, so tests must too.
    Calendar(identifier: .gregorian).startOfDay(for: d)
}

private func dayOffset(_ days: Int, from anchor: Date = fixedToday) -> Date {
    startOfDay(anchor).addingTimeInterval(Double(days) * 86_400)
}

private func checking(balance: Decimal, id: String = "acct-c") -> FinanceAccount {
    FinanceAccount(
        id: id, institutionId: "inst", institutionName: "Bank",
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

/// Tests the daily-balance series exposed on [[BalanceProjection]].
/// The series is one entry per day from `today` through
/// `today + horizonDays`, where each value is the end-of-day projected
/// checking balance derived from the same running-balance walk that
/// `firstZeroCrossing` (now `runningBalanceWalk`) executes internally.
@Suite("BalanceProjection daily series")
struct BalanceProjectionDailySeriesTests {

    @Test("zero horizon yields a single anchor point")
    func emptyHorizon() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 1_000)],
            recurrings: [],
            incomeRecurrings: [],
            horizonDays: 0,
            today: fixedToday
        )
        // A zero-day horizon is degenerate — the series should still be
        // non-empty (one point at today) so the chart has an anchor and
        // doesn't try to render across an empty axis.
        #expect(p.dailyBalanceSeries.count == 1)
        #expect(p.dailyBalanceSeries.first?.amount == Decimal(1_000))
    }

    @Test("30-day horizon with no flows is flat at starting balance")
    func flatBalance() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 2_400)],
            recurrings: [],
            incomeRecurrings: [],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.dailyBalanceSeries.count == 31)
        for point in p.dailyBalanceSeries {
            #expect(point.amount == Decimal(2_400))
        }
        // First point at today; last at today + 30d.
        #expect(p.dailyBalanceSeries.first?.date == startOfDay(fixedToday))
        #expect(p.dailyBalanceSeries.last?.date == dayOffset(30))
    }

    @Test("single debit produces a step-down on the hit date")
    func singleDebitStep() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 1_000)],
            recurrings: [
                // Use cadence 90d so it only fires once in a 30d window.
                recurring(merchant: "Rent", amount: 300, cadenceDays: 90, nextInDays: 10, category: .other)
            ],
            incomeRecurrings: [],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.dailyBalanceSeries.count == 31)
        // Days 0..9 (pre-debit) hold the starting balance; day 10
        // onward sits 300 lower.
        for i in 0..<10 {
            #expect(p.dailyBalanceSeries[i].amount == Decimal(1_000))
        }
        for i in 10...30 {
            #expect(p.dailyBalanceSeries[i].amount == Decimal(700))
        }
    }

    @Test("mix of debits and credits matches manual running balance")
    func mixedFlowsManualWalk() {
        // Starting 500. Day 3 credit +1,000. Day 10 debit -200.
        // Day 20 debit -100. End balance should be 1,200; the
        // series should mirror that step pattern day-by-day.
        let p = BalanceProjector.project(
            accounts: [checking(balance: 500)],
            recurrings: [
                recurring(merchant: "Rent", amount: 200, cadenceDays: 90, nextInDays: 10, category: .other),
                recurring(merchant: "Spotify", amount: 100, cadenceDays: 90, nextInDays: 20)
            ],
            incomeRecurrings: [
                recurring(merchant: "Payroll", amount: 1_000, cadenceDays: 90, nextInDays: 3, category: .income)
            ],
            horizonDays: 30,
            today: fixedToday
        )
        #expect(p.dailyBalanceSeries.count == 31)
        // Days 0..2 = 500
        // Days 3..9 = 1,500 (after payroll)
        // Days 10..19 = 1,300 (after rent)
        // Days 20..30 = 1,200 (after spotify)
        let expected: [Decimal] = (0...30).map { day in
            switch day {
            case 0...2:    return Decimal(500)
            case 3...9:    return Decimal(1_500)
            case 10...19:  return Decimal(1_300)
            default:       return Decimal(1_200)
            }
        }
        for (i, point) in p.dailyBalanceSeries.enumerated() {
            #expect(point.amount == expected[i],
                    "day \(i) expected \(expected[i]) got \(point.amount)")
        }
    }
}
