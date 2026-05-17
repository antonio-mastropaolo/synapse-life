import Foundation
import Testing
@testable import Models
@testable import Features

private let fixedToday = Date(timeIntervalSince1970: 1_747_440_000) // 2026-05-17

private func makeTx(
    id: String,
    amount: Decimal,
    name: String,
    merchantName: String? = nil,
    daysAgo: Int,
    category: String = "Transfers"
) -> Transaction {
    let date = fixedToday.addingTimeInterval(-Double(daysAgo) * 86_400)
    return Transaction(
        id: id,
        accountId: "acct",
        accountName: "Checking",
        amount: amount,
        currency: "USD",
        date: date,
        name: name,
        merchantName: merchantName,
        category: .knownCategory(category),
        subcategory: nil,
        pending: false
    )
}

@Suite("AnomalyExplainerReducer")
struct AnomalyExplainerReducerTests {

    @Test func detectsSelfTransferWhenCounterpartyMatchesAccountName() {
        let anomaly = makeTx(
            id: "zelle.big",
            amount: -400,
            name: "Zelle Payment To Antonio Mastropaolo",
            merchantName: "Antonio Mastropaolo",
            daysAgo: 0
        )
        let baseline: [Transaction] = (1...10).map { i in
            makeTx(
                id: "zelle.\(i)",
                amount: -130,
                name: "Zelle Payment",
                merchantName: "Friend",
                daysAgo: i
            )
        }
        let exp = AnomalyExplainerReducer.explain(
            transaction: anomaly,
            recentTransactions: baseline,
            accountNames: ["antonio mastropaolo"]
        )
        #expect(exp.body.contains("self-transfer"))
        // Suggested actions include "Mark as transfer".
        #expect(exp.suggestedActions.contains { $0.kind == .markAsTransfer })
    }

    @Test func ratioPhraseUsesActualBaselineMean() {
        // Baseline mean = 100; anomaly = 400 → ratio 4x.
        let baseline: [Transaction] = (1...10).map { i in
            makeTx(id: "b\(i)", amount: -100, name: "Other Zelle", daysAgo: i)
        }
        let anomaly = makeTx(id: "a", amount: -400, name: "Big Zelle", daysAgo: 0)
        let exp = AnomalyExplainerReducer.explain(
            transaction: anomaly,
            recentTransactions: baseline,
            accountNames: []
        )
        // 4.0× the typical transfers size
        #expect(exp.body.contains("4.0×") || exp.body.contains("4.0x"))
    }

    @Test func citationsIncludeAnomalyAndTopBaselineRows() {
        let baseline = (1...5).map { i in
            makeTx(id: "b\(i)", amount: -Decimal(i * 50), name: "Zelle", daysAgo: i)
        }
        let anomaly = makeTx(id: "anom", amount: -1000, name: "Big Zelle", daysAgo: 0)
        let exp = AnomalyExplainerReducer.explain(
            transaction: anomaly,
            recentTransactions: baseline,
            accountNames: []
        )
        // First citation is the anomaly itself.
        #expect(exp.citations.first == "anom")
        // Citations should reference the three largest baseline rows
        // (b5, b4, b3 = $250, $200, $150).
        let rest = Set(exp.citations.dropFirst())
        #expect(rest.contains("b5"))
        #expect(rest.contains("b4"))
        #expect(rest.contains("b3"))
    }

    @Test func bodyIsTwoToThreeSentences() {
        let baseline = (1...8).map { i in
            makeTx(id: "b\(i)", amount: -90, name: "Zelle", daysAgo: i)
        }
        let anomaly = makeTx(id: "a", amount: -300, name: "Big Zelle", daysAgo: 0)
        let exp = AnomalyExplainerReducer.explain(
            transaction: anomaly,
            recentTransactions: baseline,
            accountNames: []
        )
        // Count terminating periods. Allow 2 or 3.
        let periods = exp.body.filter { $0 == "." }.count
        #expect(periods >= 2 && periods <= 4)
    }

    @Test func suggestedActionsDifferForSelfTransferVsRegular() {
        let baseline = (1...5).map { i in
            makeTx(id: "b\(i)", amount: -100, name: "Zelle", daysAgo: i)
        }
        let selfTransfer = makeTx(
            id: "self",
            amount: -500,
            name: "Zelle Payment To Antonio",
            merchantName: "Antonio",
            daysAgo: 0
        )
        let regular = makeTx(id: "regular", amount: -500, name: "Zelle To Plumber", daysAgo: 0)
        let s = AnomalyExplainerReducer.explain(
            transaction: selfTransfer,
            recentTransactions: baseline,
            accountNames: ["antonio"]
        )
        let r = AnomalyExplainerReducer.explain(
            transaction: regular,
            recentTransactions: baseline,
            accountNames: []
        )
        #expect(s.suggestedActions.first?.kind == .markAsTransfer)
        #expect(r.suggestedActions.first?.kind == .investigate)
    }
}
