import Foundation
import Testing
@testable import Models
@testable import Features

@Suite("ActivityComposer")
struct ActivityComposerTests {

    private let now = Date(timeIntervalSince1970: 1_716_000_000) // 2024-05-18T08:00:00Z

    private func tx(
        id: String,
        daysAgo: Int,
        amount: Decimal,
        merchant: String,
        category: TransactionCategory = .knownCategory("food"),
        pending: Bool = false
    ) -> Transaction {
        Transaction(
            id: id,
            accountId: "acc-1",
            accountName: "Checking",
            amount: amount,
            currency: "USD",
            date: Date(timeInterval: TimeInterval(-daysAgo) * 86_400, since: now),
            name: merchant,
            merchantName: merchant,
            category: category,
            subcategory: nil,
            pending: pending
        )
    }

    private func recurring(
        id: String,
        merchant: String,
        daysAhead: Int,
        amount: Decimal = 9.99,
        txnIds: [String] = [],
        isIncome: Bool = false
    ) -> Recurring {
        Recurring(
            id: id,
            merchant: merchant,
            category: "subscriptions",
            medianAmount: amount,
            cadenceDays: 30,
            lastSeen: Date(timeInterval: TimeInterval(-30) * 86_400, since: now),
            predictedNext: Date(timeInterval: TimeInterval(daysAhead) * 86_400, since: now),
            occurrenceCount: 4,
            confidence: 0.9,
            transactionIds: txnIds,
            isIncome: isIncome
        )
    }

    private func signal(
        id: String,
        kind: ProactiveSignal.Kind,
        headline: String,
        subjectId: String? = nil,
        daysAgo: Int = 0,
        severity: ProactiveSignal.Severity = .info
    ) -> ProactiveSignal {
        ProactiveSignal(
            id: id,
            kind: kind,
            headline: headline,
            body: "body for \(id)",
            subjectId: subjectId,
            date: Date(timeInterval: TimeInterval(-daysAgo) * 86_400, since: now),
            severity: severity
        )
    }

    @Test func mapsThreeSourcesIntoUnifiedReverseChronologicalFeed() {
        let result = ActivityComposer.compose(
            transactions: [
                tx(id: "t1", daysAgo: 0, amount: -12, merchant: "Cafe"),
                tx(id: "t2", daysAgo: 2, amount: -40, merchant: "Whole Foods")
            ],
            recurrings: [
                recurring(id: "r1", merchant: "Netflix", daysAhead: 5)
            ],
            signals: [
                signal(id: "s1", kind: .newRecurring, headline: "New: SiriusXM", daysAgo: 1)
            ],
            now: now
        )

        let ids = result.map(\.id)
        #expect(ids == ["bill:r1", "txn:t1", "signal:s1", "txn:t2"])
    }

    @Test func skipsPendingTransactions() {
        let result = ActivityComposer.compose(
            transactions: [
                tx(id: "t1", daysAgo: 0, amount: -10, merchant: "Cafe", pending: true),
                tx(id: "t2", daysAgo: 0, amount: -20, merchant: "Bar")
            ],
            recurrings: [],
            signals: [],
            now: now
        )
        #expect(result.map(\.id) == ["txn:t2"])
    }

    @Test func suppressesTransactionsCoveredByARecurring() {
        let r = recurring(id: "r1", merchant: "Netflix", daysAhead: 5, txnIds: ["t1"])
        let result = ActivityComposer.compose(
            transactions: [
                tx(id: "t1", daysAgo: 0, amount: -9.99, merchant: "Netflix"),
                tx(id: "t2", daysAgo: 1, amount: -8, merchant: "Cafe")
            ],
            recurrings: [r],
            signals: [],
            now: now
        )
        // t1 is suppressed because it's already explained by r1.
        #expect(result.map(\.id) == ["bill:r1", "txn:t2"])
    }

    @Test func suppressesRecurringWhenAnUpcomingBillSignalAlreadyExplainsIt() {
        let r = recurring(id: "r1", merchant: "Netflix", daysAhead: 5)
        let s = signal(
            id: "s1",
            kind: .upcomingBill,
            headline: "Netflix due in 5 days",
            subjectId: "r1",
            daysAgo: 0,
            severity: .warning
        )
        let result = ActivityComposer.compose(
            transactions: [],
            recurrings: [r],
            signals: [s],
            now: now
        )
        // r1 is suppressed because s1 already explains it.
        #expect(result.map(\.id) == ["signal:s1"])
    }

    @Test func skipsRecurringsAlreadyInThePast() {
        let pastR = recurring(id: "r-old", merchant: "Old", daysAhead: -3)
        let futureR = recurring(id: "r-new", merchant: "New", daysAhead: 4)
        let result = ActivityComposer.compose(
            transactions: [],
            recurrings: [pastR, futureR],
            signals: [],
            now: now
        )
        #expect(result.map(\.id) == ["bill:r-new"])
    }

    @Test func respectsLimitKeepingNewest() {
        let many = (0..<10).map { i in
            tx(id: "t\(i)", daysAgo: i, amount: -5, merchant: "M\(i)")
        }
        let result = ActivityComposer.compose(
            transactions: many,
            recurrings: [],
            signals: [],
            now: now,
            limit: 3
        )
        #expect(result.count == 3)
        #expect(result.map(\.id) == ["txn:t0", "txn:t1", "txn:t2"])
    }

    @Test func mapsSignalKindsToLifeEntryKinds() {
        let result = ActivityComposer.compose(
            transactions: [],
            recurrings: [],
            signals: [
                signal(id: "a", kind: .anomalousSpend, headline: "spike", daysAgo: 0, severity: .alert),
                signal(id: "b", kind: .upcomingBill,   headline: "due",   daysAgo: 1, severity: .warning),
                signal(id: "c", kind: .newRecurring,   headline: "new",   daysAgo: 2, severity: .info)
            ],
            now: now
        )
        let kinds = result.map(\.kind)
        #expect(kinds == [.warning, .bill, .insight])
    }

    @Test func passesThroughServerDigestEntries() {
        let digest = LifeEntry(
            id: "d1",
            timestamp: Date(timeInterval: -3600, since: now),
            kind: .digest,
            text: "Weekly digest ready",
            metadata: nil
        )
        let result = ActivityComposer.compose(
            transactions: [],
            recurrings: [],
            signals: [],
            digests: [digest],
            now: now
        )
        #expect(result.map(\.id) == ["d1"])
    }

    @Test func groupedByDayReturnsBucketsNewestDayFirst() {
        let entries = ActivityComposer.compose(
            transactions: [
                tx(id: "t1", daysAgo: 0, amount: -5, merchant: "A"),
                tx(id: "t2", daysAgo: 0, amount: -6, merchant: "B"),
                tx(id: "t3", daysAgo: 2, amount: -7, merchant: "C")
            ],
            recurrings: [],
            signals: [],
            now: now
        )
        let cal = Calendar(identifier: .gregorian)
        let buckets = ActivityComposer.groupByDay(entries, calendar: cal)
        #expect(buckets.count == 2)
        #expect(buckets[0].entries.map(\.id) == ["txn:t1", "txn:t2"])
        #expect(buckets[1].entries.map(\.id) == ["txn:t3"])
        #expect(buckets[0].day > buckets[1].day)
    }
}
