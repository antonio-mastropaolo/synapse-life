import Foundation
import Testing
@testable import Models
@testable import Features

private func makeAccount(
    id: String = UUID().uuidString,
    name: String = "Checking",
    kind: AccountKind = .checking,
    balance: Decimal = 1000,
    currency: String = "USD"
) -> FinanceAccount {
    FinanceAccount(
        id: id,
        institutionId: "inst",
        institutionName: "Bank",
        name: name,
        officialName: nil,
        mask: "1234",
        kind: kind,
        currency: currency,
        currentBalance: balance,
        availableBalance: balance,
        limitAmount: nil,
        balanceCapturedAt: nil
    )
}

private func makeTx(
    id: String = UUID().uuidString,
    accountId: String = "acct",
    amount: Decimal,
    name: String = "Coffee",
    daysAgo: Int = 1,
    category: String = "Dining",
    pending: Bool = false,
    today: Date = Date()
) -> Transaction {
    let date = today.addingTimeInterval(-Double(daysAgo) * 86_400)
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

@Suite("InsightsReducer")
struct InsightsReducerTests {

    @Test func anomalyFiresWhenSingleRowExceedsMeanByMultiplier() {
        // Account has 5 small debits (~$20) and one $200 debit. The
        // $200 row is 10x mean — should fire at sensitivity 3 (2.5x).
        let accountId = "acct-1"
        var rows: [Transaction] = []
        for i in 0..<5 {
            rows.append(makeTx(id: "t\(i)", accountId: accountId, amount: -20, name: "Small \(i)"))
        }
        rows.append(makeTx(id: "tBig", accountId: accountId, amount: -200, name: "Big Charge"))
        let result = InsightsReducer.anomaly(transactions: rows, sensitivity: 3)
        #expect(result != nil)
        #expect(result?.kind == .anomaly)
        #expect(result?.accountId == accountId)
        #expect(result?.severity == .warning)
    }

    @Test func anomalyIgnoresPendingRows() {
        let accountId = "acct-1"
        var rows: [Transaction] = []
        for i in 0..<5 {
            rows.append(makeTx(id: "t\(i)", accountId: accountId, amount: -20))
        }
        rows.append(makeTx(id: "tBig", accountId: accountId, amount: -200, name: "Pending Big", pending: true))
        // The big row is pending; should NOT be flagged.
        let result = InsightsReducer.anomaly(transactions: rows, sensitivity: 3)
        #expect(result == nil)
    }

    @Test func anomalyDoesNotFireWhenAllOutflowsAreSimilar() {
        let accountId = "acct-1"
        var rows: [Transaction] = []
        for i in 0..<10 {
            rows.append(makeTx(id: "t\(i)", accountId: accountId, amount: Decimal(-20 - i)))
        }
        let result = InsightsReducer.anomaly(transactions: rows, sensitivity: 3)
        #expect(result == nil)
    }

    @Test func anomalySensitivityRescalesThreshold() {
        // At sensitivity 5 the threshold is 1.5x — a row 2x mean should
        // fire. At sensitivity 1 the threshold is 4x and the same row
        // must NOT fire.
        let accountId = "acct-1"
        var rows: [Transaction] = []
        for _ in 0..<5 {
            rows.append(makeTx(accountId: accountId, amount: -10))
        }
        rows.append(makeTx(accountId: accountId, amount: -25, name: "Larger"))
        // Mean of 5x10 + 25 = 75/6 = 12.5. $25 / $12.5 = 2.0x.
        #expect(InsightsReducer.anomaly(transactions: rows, sensitivity: 5) != nil)
        #expect(InsightsReducer.anomaly(transactions: rows, sensitivity: 1) == nil)
    }

    @Test func forecastFiresOnChecking() {
        let today = Date(timeIntervalSince1970: 1_715_000_000)
        let account = makeAccount(id: "chk", kind: .checking, balance: 600)
        // Build 30 days of $20/day outflows so perDay = $20, runway ~30 days.
        var rows: [Transaction] = []
        for d in 1...30 {
            rows.append(makeTx(accountId: "chk", amount: -20, daysAgo: d, today: today))
        }
        let result = InsightsReducer.forecast(
            accounts: [account],
            transactions: rows,
            today: today
        )
        #expect(result?.kind == .forecast)
        #expect(result?.accountId == "chk")
        // 600 / 20 = 30 days.
        #expect(result?.headline.contains("30") == true)
    }

    @Test func forecastSilentWithNoDebits() {
        let result = InsightsReducer.forecast(
            accounts: [makeAccount(balance: 1000)],
            transactions: [],
            today: Date()
        )
        #expect(result == nil)
    }

    @Test func patternFiresOnLargeWeekOverWeekChange() {
        let today = Date(timeIntervalSince1970: 1_715_000_000)
        // Prior week: $10 dining; this week: $40 dining.
        let rows: [Transaction] = [
            makeTx(id: "p1", amount: -10, name: "Coffee", daysAgo: 10, category: "Dining", today: today),
            makeTx(id: "c1", amount: -40, name: "Coffee", daysAgo: 2, category: "Dining", today: today)
        ]
        let result = InsightsReducer.pattern(transactions: rows, today: today)
        #expect(result?.kind == .pattern)
        #expect(result?.headline.contains("Dining") == true)
        #expect(result?.headline.contains("more") == true)
    }

    @Test func patternSilentWithoutPriorWeekBasis() {
        let today = Date(timeIntervalSince1970: 1_715_000_000)
        let rows: [Transaction] = [
            makeTx(id: "c1", amount: -40, name: "Coffee", daysAgo: 1, today: today)
        ]
        let result = InsightsReducer.pattern(transactions: rows, today: today)
        #expect(result == nil)
    }

    @Test func narrationCapturesNetWorthAndWeekSpend() {
        let today = Date(timeIntervalSince1970: 1_715_000_000)
        let accounts: [FinanceAccount] = [
            makeAccount(name: "Checking", kind: .checking, balance: 2000),
            makeAccount(name: "Credit", kind: .credit, balance: 500)
        ]
        let rows: [Transaction] = [
            makeTx(amount: -50, name: "Lunch", daysAgo: 2, today: today),
            makeTx(amount: -30, name: "Coffee", daysAgo: 3, today: today)
        ]
        let result = InsightsReducer.narration(accounts: accounts, transactions: rows, today: today)
        #expect(result?.kind == .narration)
        // Net = 2000 - 500 = 1500. Week spend = $80.
        #expect(result?.body.contains("80") == true)
        #expect(result?.headline.contains("1,500") == true || result?.headline.contains("1500") == true)
    }

    @Test func reduceRespectsMaxCount() {
        let today = Date(timeIntervalSince1970: 1_715_000_000)
        let accounts = [makeAccount(kind: .checking, balance: 600)]
        var rows: [Transaction] = []
        for d in 1...30 {
            rows.append(makeTx(accountId: accounts[0].id, amount: -20, daysAgo: d, today: today))
        }
        rows.append(makeTx(accountId: accounts[0].id, amount: -300, name: "Big", today: today))
        let result = InsightsReducer.reduce(
            accounts: accounts,
            transactions: rows,
            today: today,
            sensitivity: 3,
            maxCount: 3
        )
        #expect(result.count <= 3)
    }
}
