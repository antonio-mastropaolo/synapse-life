import Foundation
import Testing
@testable import Models
@testable import Features

private let fixedToday = Date(timeIntervalSince1970: 1_747_440_000) // 2026-05-17

private func makeAccount(
    id: String = "acct-1",
    kind: AccountKind = .checking,
    balance: Decimal = 4_000
) -> FinanceAccount {
    FinanceAccount(
        id: id,
        institutionId: "inst",
        institutionName: "Bank",
        name: "Checking",
        officialName: nil,
        mask: "1234",
        kind: kind,
        currency: "USD",
        currentBalance: balance,
        availableBalance: balance,
        limitAmount: nil,
        balanceCapturedAt: nil
    )
}

private func makeTx(
    id: String = UUID().uuidString,
    accountId: String = "acct-1",
    amount: Decimal,
    name: String = "Coffee",
    daysAgo: Int = 1,
    category: String = "Dining",
    pending: Bool = false
) -> Transaction {
    let date = fixedToday.addingTimeInterval(-Double(daysAgo) * 86_400)
    return Transaction(
        id: id,
        accountId: accountId,
        accountName: "Checking",
        amount: amount,
        currency: "USD",
        date: date,
        name: name,
        merchantName: nil,
        category: .knownCategory(category),
        subcategory: nil,
        pending: pending
    )
}

@Suite("DigestReducer")
struct DigestReducerTests {

    @Test func greetingUsesProvidedFirstName() {
        let digest = DigestReducer.generate(
            accounts: [makeAccount()],
            transactions: [makeTx(id: "t1", amount: -20)],
            firstName: "Antonio",
            today: fixedToday
        )
        #expect(digest.greeting.contains("Antonio"))
        #expect(digest.weekEnd > digest.weekStart)
    }

    @Test func spendBulletReportsTotalAndPriorWeekDelta() {
        let txs: [Transaction] = [
            // This week: spent 100
            makeTx(id: "tw1", amount: -60, daysAgo: 1),
            makeTx(id: "tw2", amount: -40, daysAgo: 3),
            // Prior week: spent 50 — so this week is up 100%
            makeTx(id: "pw1", amount: -50, daysAgo: 9)
        ]
        let digest = DigestReducer.generate(
            accounts: [makeAccount()],
            transactions: txs,
            today: fixedToday
        )
        let spend = digest.bullets.first { $0.kind == .spend }
        #expect(spend != nil)
        #expect(spend!.headline.contains("$100"))
        #expect(spend!.body.contains("up"))
        // Top-3 citations should reference real tx IDs from this week
        let cited = Set(spend!.citations)
        #expect(cited.isSubset(of: ["tw1", "tw2"]))
    }

    @Test func incomeBulletPicksLargestDepositAsSource() {
        let txs: [Transaction] = [
            makeTx(id: "i1", amount: 3000, name: "W&M Payroll", daysAgo: 2, category: "Income"),
            makeTx(id: "i2", amount: 200, name: "Refund", daysAgo: 4, category: "Income"),
            makeTx(id: "o1", amount: -50, daysAgo: 1)
        ]
        let digest = DigestReducer.generate(
            accounts: [makeAccount()],
            transactions: txs,
            today: fixedToday
        )
        let income = digest.bullets.first { $0.kind == .income }
        #expect(income != nil)
        #expect(income!.body.contains("W&M Payroll"))
        // Citations should include both inflows
        #expect(Set(income!.citations) == Set(["i1", "i2"]))
    }

    @Test func netBulletAddsAndSubtractsCorrectly() {
        let txs: [Transaction] = [
            makeTx(id: "i1", amount: 1000, name: "Payroll", daysAgo: 2),
            makeTx(id: "o1", amount: -300, daysAgo: 1)
        ]
        let digest = DigestReducer.generate(
            accounts: [makeAccount()],
            transactions: txs,
            today: fixedToday
        )
        let net = digest.bullets.first { $0.kind == .net }
        #expect(net != nil)
        #expect(net!.headline.contains("+$700") || net!.headline.contains("+ $700"))
    }

    @Test func topCategoryBulletPicksHighestSpendCategory() {
        let txs: [Transaction] = [
            makeTx(id: "d1", amount: -100, daysAgo: 1, category: "Dining"),
            makeTx(id: "d2", amount: -90, daysAgo: 2, category: "Dining"),
            makeTx(id: "s1", amount: -150, daysAgo: 3, category: "Shopping"),
            makeTx(id: "s2", amount: -10, daysAgo: 4, category: "Shopping")
        ]
        let digest = DigestReducer.generate(
            accounts: [makeAccount()],
            transactions: txs,
            today: fixedToday
        )
        let top = digest.bullets.first { $0.kind == .topCategory }
        #expect(top != nil)
        // Dining = 190, Shopping = 160 → Dining wins.
        #expect(top!.headline.contains("Dining"))
    }

    @Test func subscriptionsBulletFiresOnKnownTokens() {
        let txs: [Transaction] = [
            makeTx(id: "sub1", amount: -15, name: "NETFLIX", daysAgo: 1, category: "Entertainment"),
            makeTx(id: "sub2", amount: -12, name: "SPOTIFY", daysAgo: 2, category: "Entertainment"),
            makeTx(id: "coffee", amount: -5, name: "Starbucks", daysAgo: 3, category: "Dining")
        ]
        let digest = DigestReducer.generate(
            accounts: [makeAccount()],
            transactions: txs,
            today: fixedToday
        )
        let subs = digest.bullets.first { $0.kind == .subscriptions }
        #expect(subs != nil)
        #expect(subs!.headline.contains("2 subscriptions"))
        #expect(Set(subs!.citations) == Set(["sub1", "sub2"]))
    }

    @Test func bulletsAreDeterministicallyOrdered() {
        let txs: [Transaction] = [
            makeTx(id: "tw1", amount: -100, daysAgo: 1, category: "Dining"),
            makeTx(id: "tw2", amount: -50, daysAgo: 2, category: "Shopping"),
            makeTx(id: "sub1", amount: -15, name: "NETFLIX", daysAgo: 3, category: "Entertainment"),
            makeTx(id: "i1", amount: 2000, name: "Payroll", daysAgo: 4, category: "Income")
        ]
        let d1 = DigestReducer.generate(accounts: [makeAccount()], transactions: txs, today: fixedToday)
        let d2 = DigestReducer.generate(accounts: [makeAccount()], transactions: txs, today: fixedToday)
        #expect(d1.bullets.map { $0.kind } == d2.bullets.map { $0.kind })
        #expect(d1.bullets.map { $0.headline } == d2.bullets.map { $0.headline })
    }

    @Test func bulletCountStaysWithinFiveToSevenForRichWeek() {
        let txs: [Transaction] = [
            makeTx(id: "i1", amount: 3000, name: "Payroll", daysAgo: 2, category: "Income"),
            makeTx(id: "d1", amount: -100, daysAgo: 1, category: "Dining"),
            makeTx(id: "d2", amount: -50, daysAgo: 1, category: "Dining"),
            makeTx(id: "d3", amount: -60, daysAgo: 2, category: "Dining"),
            makeTx(id: "d4", amount: -55, daysAgo: 3, category: "Dining"),
            // Make one row 5x the mean so the anomaly fires.
            makeTx(id: "anom", amount: -400, daysAgo: 4, category: "Dining"),
            makeTx(id: "sub1", amount: -15, name: "NETFLIX", daysAgo: 5, category: "Entertainment")
        ]
        let digest = DigestReducer.generate(
            accounts: [makeAccount(balance: 300)],
            transactions: txs,
            today: fixedToday
        )
        #expect(digest.bullets.count >= 5)
        #expect(digest.bullets.count <= 7)
    }
}
