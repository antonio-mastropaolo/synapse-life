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

private func checking(balance: Decimal, id: String = "acct-c") -> FinanceAccount {
    FinanceAccount(
        id: id, institutionId: "inst", institutionName: "Bank",
        name: "Checking", officialName: nil, mask: "1234",
        kind: .checking, currency: "USD",
        currentBalance: balance, availableBalance: balance,
        limitAmount: nil, balanceCapturedAt: nil
    )
}

private func savings(balance: Decimal) -> FinanceAccount {
    FinanceAccount(
        id: "acct-s", institutionId: "inst", institutionName: "Bank",
        name: "Savings", officialName: nil, mask: "9999",
        kind: .savings, currency: "USD",
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

@Suite("BalanceProjection")
struct BalanceProjectionTests {

    @Test("positive trajectory never hits zero")
    func positiveBalanceStaysPositive() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 5_000)],
            recurrings: [
                recurring(merchant: "Netflix", amount: 23, nextInDays: 3),
                recurring(merchant: "Spotify", amount: 17, nextInDays: 7)
            ],
            incomeRecurrings: [],
            today: fixedToday
        )
        #expect(p.projectedZeroDate == nil)
        #expect(p.startingChecking == Decimal(5_000))
        #expect(p.totalDebits == Decimal(40))
        #expect(p.predictedChargesCount == 2)
    }

    @Test("low balance + heavy bills hits zero in horizon")
    func zeroCrossing() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 200)],
            recurrings: [
                recurring(merchant: "Rent", amount: 1_850, nextInDays: 1, category: .other),
                recurring(merchant: "Netflix", amount: 22.99, nextInDays: 5)
            ],
            incomeRecurrings: [],
            today: fixedToday
        )
        #expect(p.projectedZeroDate != nil)
        // Day 1 has the rent hit; balance crosses zero then.
        let expected = fixedToday.addingTimeInterval(1 * 86_400)
        #expect(p.projectedZeroDate == expected)
    }

    @Test("income shifts the zero-crossing date later")
    func incomeOffsetShiftsZero() {
        let withoutIncome = BalanceProjector.project(
            accounts: [checking(balance: 300)],
            recurrings: [recurring(merchant: "Rent", amount: 1_850, nextInDays: 3)],
            incomeRecurrings: [],
            today: fixedToday
        )
        let withIncome = BalanceProjector.project(
            accounts: [checking(balance: 300)],
            recurrings: [recurring(merchant: "Rent", amount: 1_850, nextInDays: 3)],
            incomeRecurrings: [
                recurring(
                    merchant: "Payroll", amount: 3_000,
                    cadenceDays: 14, nextInDays: 2, category: .income
                )
            ],
            today: fixedToday
        )
        #expect(withoutIncome.projectedZeroDate != nil)
        #expect(withIncome.projectedZeroDate == nil)
        #expect(withIncome.totalCredits >= Decimal(3_000))
    }

    @Test("empty recurrings preserves starting balance")
    func emptyRecurrings() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 2_400)],
            recurrings: [], incomeRecurrings: [],
            today: fixedToday
        )
        #expect(p.startingChecking == Decimal(2_400))
        #expect(p.totalDebits == 0)
        #expect(p.totalCredits == 0)
        #expect(p.predictedChargesCount == 0)
        #expect(p.projectedZeroDate == nil)
    }

    @Test("only checking-style accounts contribute to starting balance")
    func mixedAccountsCheckingOnly() {
        let p = BalanceProjector.project(
            accounts: [
                checking(balance: 1_000),
                savings(balance: 50_000)   // ignored
            ],
            recurrings: [], incomeRecurrings: [],
            today: fixedToday
        )
        #expect(p.startingChecking == Decimal(1_000))
    }

    @Test("weekly recurring expands to multiple flows in horizon")
    func weeklyExpansion() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 1_000)],
            recurrings: [
                recurring(
                    merchant: "City Transit",
                    amount: 35, cadenceDays: 7, nextInDays: 2,
                    category: .other
                )
            ],
            incomeRecurrings: [],
            horizonDays: 30,
            today: fixedToday
        )
        // Days 2, 9, 16, 23, 30 — day 30 is at horizonEnd which is
        // exclusive, so 4 flows fit.
        #expect(p.scheduledDebits.count == 4)
        #expect(p.totalDebits == Decimal(35 * 4))
    }

    @Test("ScheduledFlow id is stable and unique within a day")
    func scheduledFlowIdentity() {
        let p = BalanceProjector.project(
            accounts: [checking(balance: 1_000)],
            recurrings: [
                recurring(merchant: "Netflix", amount: 22.99, nextInDays: 5),
                recurring(merchant: "Spotify", amount: 16.99, nextInDays: 5)
            ],
            incomeRecurrings: [],
            today: fixedToday
        )
        let ids = p.scheduledDebits.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
