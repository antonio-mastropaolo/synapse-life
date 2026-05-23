import Foundation
import Testing
@testable import Models
@testable import Features

@Suite("AccountDetailBalanceSeries — backward walk")
struct AccountDetailBalanceSeriesTests {

    private let today = AccountDetailFixtures.today

    // MARK: - Output shape

    @Test("Empty transactions → flat line at anchor across the range")
    func emptyTransactionsFlatLine() {
        let series = AccountDetailBalanceSeries.walk(
            anchor: Decimal(string: "1000.00")!,
            transactions: [],
            range: .d30,
            today: today
        )
        // .d30 → 31 points (today + 30 days back).
        #expect(series.count == 31)
        for point in series {
            #expect(point.balance == Decimal(string: "1000.00"))
        }
    }

    @Test("Output is forward-ordered (ascending date)")
    func outputForwardOrdered() {
        let series = AccountDetailBalanceSeries.walk(
            anchor: 500,
            transactions: [],
            range: .d7,
            today: today
        )
        for i in 1..<series.count {
            #expect(series[i].date > series[i - 1].date,
                    "Series must be sorted ascending; failed at index \(i)")
        }
    }

    @Test("Last point's date is today's start-of-day")
    func lastPointIsToday() {
        let series = AccountDetailBalanceSeries.walk(
            anchor: 0,
            transactions: [],
            range: .d7,
            today: today
        )
        let cal = Calendar(identifier: .gregorian)
        let startToday = cal.startOfDay(for: today)
        #expect(series.last?.date == startToday)
    }

    // MARK: - Transaction-driven walk

    @Test("A -50 debit 10 days ago produces a step: earlier balance was 50 higher")
    func debitStepBackwardIsHigher() {
        // anchor 1000 today; 10 days ago we spent 50. So 10 days ago
        // BEFORE the spend, the balance was 1050. The walker
        // subtracts the daily net from the running balance, so going
        // back the running drops by -50 (i.e. rises by 50).
        let txs = [
            AccountDetailFixtures.tx(
                id: "debit-1",
                daysAgo: 10,
                amountString: "-50.00"
            )
        ]
        let series = AccountDetailBalanceSeries.walk(
            anchor: Decimal(string: "1000.00")!,
            transactions: txs,
            range: .d30,
            today: today
        )
        // Last point (today) is the anchor.
        #expect(series.last?.balance == Decimal(string: "1000.00"))
        // Point 11 days back (12th from end) should be 1050.
        let cal = Calendar(identifier: .gregorian)
        let targetDay = cal.startOfDay(for: today.addingTimeInterval(-11 * 86_400))
        let earlier = series.first { $0.date == targetDay }
        #expect(earlier?.balance == Decimal(string: "1050.00"),
                "Pre-debit balance should be 50 higher than anchor")
    }

    @Test("A +200 credit 5 days ago produces an earlier balance that's 200 lower")
    func creditStepBackwardIsLower() {
        // anchor 1000 today; 5 days ago we received 200. So before
        // that credit, the balance was 800.
        let txs = [
            AccountDetailFixtures.tx(
                id: "credit-1",
                daysAgo: 5,
                amountString: "200.00"
            )
        ]
        let series = AccountDetailBalanceSeries.walk(
            anchor: Decimal(string: "1000.00")!,
            transactions: txs,
            range: .d30,
            today: today
        )
        let cal = Calendar(identifier: .gregorian)
        let targetDay = cal.startOfDay(for: today.addingTimeInterval(-6 * 86_400))
        let earlier = series.first { $0.date == targetDay }
        #expect(earlier?.balance == Decimal(string: "800.00"))
    }

    @Test("Pending transactions are ignored")
    func pendingIgnored() {
        let txs = [
            AccountDetailFixtures.tx(
                id: "pending-1",
                daysAgo: 5,
                amountString: "-999.00",
                pending: true
            )
        ]
        let series = AccountDetailBalanceSeries.walk(
            anchor: 100,
            transactions: txs,
            range: .d30,
            today: today
        )
        // Flat at 100 — the pending row should not change anything.
        for p in series { #expect(p.balance == 100) }
    }

    // MARK: - Range widening

    @Test("Range expansion includes proportionally more points")
    func rangeExpansionScalesPointCount() {
        let counts = AccountDetailBalanceSeries.Range.allCases.map { range -> Int in
            AccountDetailBalanceSeries.walk(
                anchor: 0,
                transactions: [],
                range: range,
                today: today
            ).count
        }
        // .d7 < .d30 < .d90 < .d1y < .all
        #expect(counts == counts.sorted(),
                "Point count should grow with range; got \(counts)")
    }
}
