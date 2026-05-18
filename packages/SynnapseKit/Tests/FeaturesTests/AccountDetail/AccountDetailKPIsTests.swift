import Foundation
import Testing
@testable import Models
@testable import Features

@Suite("AccountDetailKPIs — pure math")
struct AccountDetailKPIsTests {

    private let today = AccountDetailFixtures.today

    // MARK: - monthSpend

    @Test("monthSpend sums debits in the current calendar month")
    func monthSpendBasics() {
        // today is 2026-05-17 → current month is May 2026.
        // Two debits in May, one in April (~40 days ago → outside).
        let txs = [
            AccountDetailFixtures.tx(id: "may-1",   daysAgo: 5,  amountString: "-20.00"),
            AccountDetailFixtures.tx(id: "may-2",   daysAgo: 10, amountString: "-30.00"),
            AccountDetailFixtures.tx(id: "april-1", daysAgo: 40, amountString: "-500.00")
        ]
        let total = AccountDetailKPIs.monthSpend(from: txs, today: today)
        #expect(total == Decimal(string: "50.00"))
    }

    @Test("monthSpend ignores credits and pending")
    func monthSpendIgnoresCreditsAndPending() {
        let txs = [
            AccountDetailFixtures.tx(id: "credit",  daysAgo: 5, amountString: "100.00"),
            AccountDetailFixtures.tx(id: "pending", daysAgo: 5, amountString: "-50.00", pending: true),
            AccountDetailFixtures.tx(id: "real",    daysAgo: 5, amountString: "-25.00")
        ]
        #expect(AccountDetailKPIs.monthSpend(from: txs, today: today)
                == Decimal(string: "25.00"))
    }

    // MARK: - monthIncome

    @Test("monthIncome returns nil for liability accounts")
    func monthIncomeNilForLiability() {
        let txs = [
            AccountDetailFixtures.tx(id: "x", daysAgo: 1, amountString: "100.00")
        ]
        #expect(AccountDetailKPIs.monthIncome(
            from: txs, today: today, accountKind: .credit
        ) == nil)
        #expect(AccountDetailKPIs.monthIncome(
            from: txs, today: today, accountKind: .loan
        ) == nil)
    }

    @Test("monthIncome sums credits in the current month for non-liability")
    func monthIncomeBasics() {
        let txs = [
            AccountDetailFixtures.tx(id: "payroll-1", daysAgo: 14, amountString: "2500.00"),
            AccountDetailFixtures.tx(id: "payroll-2", daysAgo: 2,  amountString: "2500.00"),
            // April hit — outside current month.
            AccountDetailFixtures.tx(id: "april",     daysAgo: 40, amountString: "1500.00")
        ]
        #expect(AccountDetailKPIs.monthIncome(
            from: txs, today: today, accountKind: .checking
        ) == Decimal(string: "5000.00"))
    }

    // MARK: - avgDailySpend

    @Test("avgDailySpend divides trailing debits by the window")
    func avgDailySpendBasics() {
        // Three -10 debits in the trailing 30 days → 30/30 = 1.
        let txs = [
            AccountDetailFixtures.tx(id: "a", daysAgo: 1,  amountString: "-10.00"),
            AccountDetailFixtures.tx(id: "b", daysAgo: 10, amountString: "-10.00"),
            AccountDetailFixtures.tx(id: "c", daysAgo: 20, amountString: "-10.00")
        ]
        #expect(AccountDetailKPIs.avgDailySpend(from: txs, today: today)
                == Decimal(string: "1.00"))
    }

    @Test("avgDailySpend ignores rows outside the window")
    func avgDailySpendWindow() {
        let txs = [
            AccountDetailFixtures.tx(id: "outside", daysAgo: 90, amountString: "-300.00")
        ]
        #expect(AccountDetailKPIs.avgDailySpend(from: txs, today: today)
                == 0)
    }

    // MARK: - daysSinceCapture

    @Test("daysSinceCapture returns the calendar-day difference")
    func daysSinceCaptureBasics() {
        let acct = AccountDetailFixtures.account(capturedDaysAgo: 7)
        #expect(AccountDetailKPIs.daysSinceCapture(acct, today: today) == 7)
    }

    @Test("daysSinceCapture returns nil when no capture timestamp")
    func daysSinceCaptureNilWhenMissing() {
        let acct = AccountDetailFixtures.account(capturedDaysAgo: nil)
        #expect(AccountDetailKPIs.daysSinceCapture(acct, today: today) == nil)
    }
}
