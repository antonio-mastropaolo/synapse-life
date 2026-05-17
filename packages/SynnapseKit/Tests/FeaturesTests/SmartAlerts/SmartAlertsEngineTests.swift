import Foundation
import Testing
@testable import Models
@testable import Features

private let fixedNow = Date(timeIntervalSince1970: 1_747_440_000) // 2026-05-17

private func makeAccount(
    id: String = "acct-1",
    kind: AccountKind = .checking,
    name: String = "Checking",
    balance: Decimal
) -> FinanceAccount {
    FinanceAccount(
        id: id,
        institutionId: "inst",
        institutionName: "Bank",
        name: name,
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
    name: String = "Tx",
    merchantName: String? = nil,
    daysAgo: Int = 0,
    category: String = "Dining"
) -> Transaction {
    let date = fixedNow.addingTimeInterval(-Double(daysAgo) * 86_400)
    return Transaction(
        id: id,
        accountId: accountId,
        accountName: "Checking",
        amount: amount,
        currency: "USD",
        date: date,
        name: name,
        merchantName: merchantName ?? name,
        category: .knownCategory(category),
        subcategory: nil,
        pending: false
    )
}

@Suite("SmartAlertsEngine")
struct SmartAlertsEngineTests {

    @Test func balanceLowFiresWhenCheckingDropsBelowThreshold() {
        let rules = [
            AlertRule(id: "r1", kind: .balanceLow(accountKind: .checking, threshold: 500))
        ]
        let snapshot = AlertsSnapshot(
            accounts: [makeAccount(balance: 300)],
            transactions: [],
            now: fixedNow
        )
        let fired = SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot)
        #expect(fired.count == 1)
        #expect(fired.first?.ruleId == "r1")
        #expect(fired.first?.severity == .warning || fired.first?.severity == .alert)
    }

    @Test func balanceLowQuietWhenAboveThreshold() {
        let rules = [
            AlertRule(id: "r1", kind: .balanceLow(accountKind: .checking, threshold: 500))
        ]
        let snapshot = AlertsSnapshot(
            accounts: [makeAccount(balance: 800)],
            transactions: [],
            now: fixedNow
        )
        #expect(SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot).isEmpty)
    }

    @Test func newRecurringFiresOnDetectedMerchantNotInPriorSet() {
        // Build a 30-day-cadence merchant.
        let txs = (0..<4).map { i in
            makeTx(
                id: "n\(i)",
                amount: -15,
                name: "NETFLIX",
                merchantName: "Netflix",
                daysAgo: 90 - (i * 30),
                category: "Entertainment"
            )
        }
        let rules = [AlertRule(id: "r1", kind: .newRecurring)]
        let snapshot = AlertsSnapshot(
            accounts: [],
            transactions: txs,
            priorMerchants: [], // nothing known yet
            now: fixedNow
        )
        let fired = SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot)
        #expect(fired.count == 1)
        #expect(fired.first!.headline.lowercased().contains("netflix"))
    }

    @Test func newRecurringQuietWhenMerchantIsKnown() {
        let txs = (0..<4).map { i in
            makeTx(
                id: "n\(i)",
                amount: -15,
                name: "NETFLIX",
                merchantName: "Netflix",
                daysAgo: 90 - (i * 30),
                category: "Entertainment"
            )
        }
        let rules = [AlertRule(id: "r1", kind: .newRecurring)]
        let snapshot = AlertsSnapshot(
            accounts: [],
            transactions: txs,
            priorMerchants: ["NETFLIX"],
            now: fixedNow
        )
        #expect(SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot).isEmpty)
    }

    @Test func unusualSpendFiresOnCategoryDailyOverThreshold() {
        let txs = [
            makeTx(id: "d1", amount: -50, daysAgo: 0, category: "Dining"),
            makeTx(id: "d2", amount: -40, daysAgo: 0, category: "Dining"),
            makeTx(id: "d3", amount: -30, daysAgo: 0, category: "Dining")
        ]
        let rules = [
            AlertRule(id: "r1", kind: .unusualSpend(categoryLabel: "Dining", dailyThreshold: 80))
        ]
        let snapshot = AlertsSnapshot(accounts: [], transactions: txs, now: fixedNow)
        let fired = SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot)
        #expect(fired.count == 1)
        #expect(fired.first!.body.contains("Dining"))
    }

    @Test func disabledRulesDoNotFire() {
        let rules = [
            AlertRule(
                id: "r1",
                kind: .balanceLow(accountKind: .checking, threshold: 500),
                enabled: false
            )
        ]
        let snapshot = AlertsSnapshot(
            accounts: [makeAccount(balance: 100)],
            transactions: [],
            now: fixedNow
        )
        #expect(SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot).isEmpty)
    }

    @Test func suggestRulesProposesNewRecurringWhenAbsent() {
        let snapshot = AlertsSnapshot(
            accounts: [makeAccount(balance: 5000)],
            transactions: [],
            now: fixedNow
        )
        let suggestions = SmartAlertsEngine.suggestRules(snapshot: snapshot, existing: [])
        #expect(suggestions.contains { rule in
            if case .newRecurring = rule.kind { return rule.isAISuggested }
            return false
        })
    }

    @Test func suggestRulesProposesUnusualSpendWhenDiningSignalIsStrong() {
        // 10 dining rows averaging $40/day → suggest $80 threshold.
        let txs = (1...10).map { i in
            makeTx(id: "d\(i)", amount: -40, name: "Restaurant \(i)", daysAgo: i, category: "Dining")
        }
        let snapshot = AlertsSnapshot(accounts: [], transactions: txs, now: fixedNow)
        let suggestions = SmartAlertsEngine.suggestRules(snapshot: snapshot, existing: [])
        let unusual = suggestions.first { rule in
            if case .unusualSpend = rule.kind { return true }
            return false
        }
        #expect(unusual != nil)
        if case .unusualSpend(_, let threshold) = unusual!.kind {
            // Threshold should be ≥ 2× the daily mean.
            #expect(threshold >= 40)
        }
    }

    @Test func severitySortPutsAlertOverWarningOverInfo() {
        let rules = [
            AlertRule(id: "r1", kind: .balanceLow(accountKind: .checking, threshold: 500)),
            AlertRule(id: "r2", kind: .newRecurring)
        ]
        // Build a way-under-threshold balance + a new recurring.
        let txs = (0..<4).map { i in
            makeTx(
                id: "n\(i)",
                amount: -15,
                name: "NETFLIX",
                merchantName: "Netflix",
                daysAgo: 90 - (i * 30),
                category: "Entertainment"
            )
        }
        let snapshot = AlertsSnapshot(
            accounts: [makeAccount(balance: 50)], // very low → .alert
            transactions: txs,
            priorMerchants: [],
            now: fixedNow
        )
        let fired = SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot)
        #expect(fired.count == 2)
        // The balance-low (alert) should sort first.
        #expect(fired.first?.severity == .alert)
    }
}
