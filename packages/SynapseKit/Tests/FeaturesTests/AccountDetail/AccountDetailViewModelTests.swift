import Foundation
import Testing
@testable import Models
@testable import Features

@Suite("AccountDetailViewModel — projection")
@MainActor
struct AccountDetailViewModelTests {

    private let today = AccountDetailFixtures.today

    private func vm(
        kind: AccountKind = .checking,
        balance: Decimal? = Decimal(string: "1000.00"),
        allTransactions: [Transaction] = []
    ) -> AccountDetailViewModel {
        AccountDetailViewModel(
            account: AccountDetailFixtures.account(
                id: "acc-test",
                kind: kind,
                currentBalance: balance
            ),
            allTransactions: allTransactions,
            today: today
        )
    }

    // MARK: - Scoping

    @Test("scopedTransactions filters by accountId")
    func scopedTransactionsFiltersByAccount() {
        let mine = AccountDetailFixtures.tx(
            id: "mine-1", daysAgo: 1, amountString: "-10",
            accountId: "acc-test"
        )
        let theirs = AccountDetailFixtures.tx(
            id: "theirs-1", daysAgo: 1, amountString: "-99",
            accountId: "other-account"
        )
        let v = vm(allTransactions: [mine, theirs])
        let scoped = v.scopedTransactions
        #expect(scoped.count == 1)
        #expect(scoped.first?.id == "mine-1")
    }

    @Test("scopedTransactions is newest-first and capped at 50")
    func scopedTransactionsNewestFirstCapped() {
        // 80 transactions over 80 days, ascending order.
        let txs = (0..<80).map { i in
            AccountDetailFixtures.tx(
                id: "t-\(i)",
                daysAgo: 80 - i,
                amountString: "-1.00"
            )
        }
        let v = vm(allTransactions: txs)
        let scoped = v.scopedTransactions
        #expect(scoped.count == 50)
        // First row should be the newest (daysAgo = 1, i = 79).
        #expect(scoped.first?.id == "t-79")
        // Output must be sorted descending by date.
        for i in 1..<scoped.count {
            #expect(scoped[i - 1].date >= scoped[i].date)
        }
    }

    // MARK: - Empty state

    @Test("Empty transactions → KPIs are all zero, balance series flat at anchor")
    func emptyStateZeroKPIs() {
        let v = vm(balance: Decimal(string: "500.00"), allTransactions: [])
        let kpis = v.kpis
        #expect(kpis.monthSpend == 0)
        #expect(kpis.monthIncome == 0)
        #expect(kpis.avgDailySpend == 0)
        for point in v.balanceSeries {
            #expect(point.balance == Decimal(string: "500.00"))
        }
    }

    // MARK: - Liability accounts

    @Test("Credit account hides monthIncome (nil)")
    func creditAccountMonthIncomeNil() {
        let v = vm(kind: .credit, allTransactions: [])
        #expect(v.kpis.monthIncome == nil)
    }

    // MARK: - Recurrings

    @Test("Recurrings are detected only against account-scoped transactions")
    func recurringsAreAccountScoped() {
        // 6 monthly charges to THIS account; 6 to a different one.
        // Detector requires ≥ 3 in a 180-day window; the off-account
        // ones must not surface here.
        var txs: [Transaction] = []
        for i in 0..<6 {
            txs.append(AccountDetailFixtures.tx(
                id: "mine-\(i)",
                daysAgo: 15 + i * 30,
                amountString: "-20.00",
                accountId: "acc-test",
                merchant: "Anthropic"
            ))
        }
        for i in 0..<6 {
            txs.append(AccountDetailFixtures.tx(
                id: "theirs-\(i)",
                daysAgo: 15 + i * 30,
                amountString: "-99.00",
                accountId: "other-account",
                merchant: "Netflix"
            ))
        }
        let v = vm(allTransactions: txs)
        let names = v.recurrings.map(\.merchant)
        #expect(names.contains(where: { $0.lowercased().contains("anthropic") }))
        #expect(!names.contains(where: { $0.lowercased().contains("netflix") }),
                "Off-account recurrings must not leak through")
    }

    // MARK: - KPI integration

    @Test("monthSpend rolls up the account-scoped debits")
    func monthSpendIntegration() {
        let txs = [
            AccountDetailFixtures.tx(id: "x1", daysAgo: 2,  amountString: "-25.00"),
            AccountDetailFixtures.tx(id: "x2", daysAgo: 12, amountString: "-15.00"),
            // Off-account — must be ignored.
            AccountDetailFixtures.tx(
                id: "off", daysAgo: 2, amountString: "-500.00",
                accountId: "other-account"
            )
        ]
        let v = vm(allTransactions: txs)
        #expect(v.kpis.monthSpend == Decimal(string: "40.00"))
    }

    // MARK: - Range mutation

    @Test("Mutating range changes balanceSeries point count")
    func rangeMutationResizesSeries() {
        let v = vm()
        v.range = .d7
        let short = v.balanceSeries.count
        v.range = .d90
        let long = v.balanceSeries.count
        #expect(long > short)
    }

    // MARK: - Sync error slot

    @Test("syncError defaults to nil; can be set externally")
    func syncErrorSlot() {
        let v = vm()
        #expect(v.syncError == nil)
        v.syncError = "Connection refresh failed"
        #expect(v.syncError == "Connection refresh failed")
    }

    // MARK: - Balance anchor

    @Test("Balance series ends at the account's currentBalance")
    func balanceSeriesEndsAtAnchor() {
        let v = vm(balance: Decimal(string: "1234.56"))
        #expect(v.balanceSeries.last?.balance == Decimal(string: "1234.56"))
    }

    @Test("Nil currentBalance → series anchored at zero")
    func nilBalanceAnchorsAtZero() {
        let v = vm(balance: nil)
        #expect(v.balanceSeries.last?.balance == 0)
    }
}
