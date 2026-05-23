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
    name: String = "Tx",
    merchantName: String? = nil,
    daysAgo: Int,
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
        merchantName: merchantName ?? name,
        category: .knownCategory(category),
        subcategory: nil,
        pending: pending
    )
}

@Suite("ForecastReducer")
struct ForecastReducerTests {

    @Test func projectionLengthMatchesHorizon() {
        // 30 days of small uniform debits.
        let txs = (1...30).map { day in
            makeTx(id: "t\(day)", amount: -10, daysAgo: day)
        }
        let f = ForecastReducer.project(
            account: makeAccount(balance: 1000),
            transactions: txs,
            today: fixedToday,
            horizonDays: 30
        )
        #expect(f.series.count == 30)
    }

    @Test func zeroCrossingFiresWhenDriftEatsBalance() {
        // Spend 100/day for 30 days, balance 200 — should zero in ~2 days.
        let txs = (1...30).map { day in
            makeTx(id: "t\(day)", amount: -100, daysAgo: day)
        }
        let f = ForecastReducer.project(
            account: makeAccount(balance: 200),
            transactions: txs,
            today: fixedToday,
            horizonDays: 30
        )
        #expect(f.zeroCrossing != nil)
        // The crossing date is in the projection window (today, today+30].
        let crossing = f.zeroCrossing!
        #expect(crossing > fixedToday)
        let horizonEnd = fixedToday.addingTimeInterval(30 * 86_400)
        #expect(crossing <= horizonEnd)
    }

    @Test func zeroCrossingNilWhenIncomeOffsetsSpend() {
        // Income equals spend → drift ~0 → no crossing.
        var txs: [Transaction] = []
        for d in 1...30 {
            txs.append(makeTx(id: "o\(d)", amount: -50, daysAgo: d))
            txs.append(makeTx(id: "i\(d)", amount: 50, daysAgo: d, category: "Income"))
        }
        let f = ForecastReducer.project(
            account: makeAccount(balance: 1000),
            transactions: txs,
            today: fixedToday,
            horizonDays: 30
        )
        #expect(f.zeroCrossing == nil)
    }

    @Test func confidenceBandWidensOverTime() {
        // Non-uniform debits → nonzero stdev → band must widen.
        let txs: [Transaction] = [
            makeTx(id: "a", amount: -200, daysAgo: 1),
            makeTx(id: "b", amount: -10, daysAgo: 2),
            makeTx(id: "c", amount: -50, daysAgo: 3),
            makeTx(id: "d", amount: -300, daysAgo: 4),
            makeTx(id: "e", amount: -20, daysAgo: 5)
        ]
        let f = ForecastReducer.project(
            account: makeAccount(balance: 5000),
            transactions: txs,
            today: fixedToday,
            horizonDays: 14
        )
        let widthDay1 = f.series[0].upperBound - f.series[0].lowerBound
        let widthDay10 = f.series[9].upperBound - f.series[9].lowerBound
        #expect(widthDay10 > widthDay1)
    }

    @Test func predictedRechargeSubtractsOnExpectedDay() {
        // No debits except a single predicted Sirius XM charge in 3 days
        // on a 5000-balance account. The projection should step down
        // by $37 on day 3 vs day 2.
        let predicted = PredictedCharge(
            id: "sirius",
            merchantName: "Sirius XM",
            amount: 37,
            date: fixedToday.addingTimeInterval(3 * 86_400)
        )
        let f = ForecastReducer.project(
            account: makeAccount(balance: 5000),
            transactions: [],
            predictedCharges: [predicted],
            today: fixedToday,
            horizonDays: 7
        )
        // With zero history, drift = 0 and stdev = 0, so the only
        // movement should be the charge step on day 3 (index 2).
        let day2 = f.series[1].balance
        let day3 = f.series[2].balance
        #expect(day2 - day3 == 37)
    }

    @Test func predictedRecurringsFindsMonthlyMerchant() {
        // 4 charges, each ~30 days apart for "SIRIUS XM" at $37.
        let txs = (0..<4).map { i in
            makeTx(
                id: "s\(i)",
                amount: -37,
                name: "SIRIUS XM",
                merchantName: "Sirius XM",
                daysAgo: 90 - (i * 30),
                category: "Entertainment"
            )
        }
        let predicted = ForecastReducer.predictedRecurrings(transactions: txs, today: fixedToday)
        #expect(predicted.count == 1)
        #expect(predicted.first?.merchantName.lowercased().contains("sirius") == true)
        #expect(predicted.first!.amount == 37)
        // Next charge: last seen on day 0 (today-ish) + 30 days ≈ today+30
        let next = predicted.first!.date
        let delta = next.timeIntervalSince(fixedToday) / 86_400
        #expect(delta > 0 && delta < 60)
    }

    @Test func predictedRecurringsSkipsOneOffMerchants() {
        let txs = [
            makeTx(id: "a", amount: -25, name: "RANDOM MERCHANT", daysAgo: 30, category: "Shopping"),
            makeTx(id: "b", amount: -25, name: "OTHER MERCHANT", daysAgo: 15, category: "Shopping")
        ]
        let predicted = ForecastReducer.predictedRecurrings(transactions: txs, today: fixedToday)
        #expect(predicted.isEmpty)
    }

    @Test func nextThirtyDaysTotalSumsAllChargesInWindow() {
        let charges: [PredictedCharge] = [
            PredictedCharge(id: "a", merchantName: "Netflix", amount: 15, date: fixedToday.addingTimeInterval(5 * 86_400)),
            PredictedCharge(id: "b", merchantName: "Spotify", amount: 12, date: fixedToday.addingTimeInterval(10 * 86_400)),
            PredictedCharge(id: "c", merchantName: "Outside", amount: 99, date: fixedToday.addingTimeInterval(45 * 86_400))
        ]
        let f = ForecastReducer.project(
            account: makeAccount(balance: 1000),
            transactions: [],
            predictedCharges: charges,
            today: fixedToday,
            horizonDays: 30
        )
        #expect(f.nextThirtyDaysTotal == 27)  // 15 + 12, "Outside" is past 30 days
    }
}
