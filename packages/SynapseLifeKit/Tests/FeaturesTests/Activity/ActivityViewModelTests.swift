import Foundation
import Testing
@testable import Models
@testable import Features

@Suite("ActivityViewModel")
struct ActivityViewModelTests {

    private let now = Date(timeIntervalSince1970: 1_716_000_000)

    private func tx(_ id: String, daysAgo: Int) -> Transaction {
        Transaction(
            id: id,
            accountId: "acc",
            accountName: "Checking",
            amount: -10,
            currency: "USD",
            date: Date(timeInterval: TimeInterval(-daysAgo) * 86_400, since: now),
            name: "Merchant \(id)",
            merchantName: "Merchant \(id)",
            category: .knownCategory("food"),
            subcategory: nil,
            pending: false
        )
    }

    private func recurring(_ id: String, daysAhead: Int) -> Recurring {
        Recurring(
            id: id,
            merchant: "Recur \(id)",
            category: "subscriptions",
            medianAmount: 9.99,
            cadenceDays: 30,
            lastSeen: Date(timeInterval: -30 * 86_400, since: now),
            predictedNext: Date(timeInterval: TimeInterval(daysAhead) * 86_400, since: now),
            occurrenceCount: 4,
            confidence: 0.9,
            transactionIds: [],
            isIncome: false
        )
    }

    private func signal(_ id: String, kind: ProactiveSignal.Kind, subject: String? = nil) -> ProactiveSignal {
        ProactiveSignal(
            id: id,
            kind: kind,
            headline: "headline \(id)",
            body: "body \(id)",
            subjectId: subject,
            date: now,
            severity: .warning
        )
    }

    @MainActor
    private func makeVM(
        snapshot: ActivitySnapshot
    ) -> ActivityViewModel {
        ActivityViewModel(
            now: { self.now },
            source: ClosureActivitySource(snapshot: snapshot)
        )
    }

    @Test @MainActor
    func startsIdleAndTransitionsToReadyOnLoad() async {
        let vm = makeVM(snapshot: ActivitySnapshot(
            transactions: [tx("t1", daysAgo: 0)],
            recurrings: [],
            signals: [],
            digests: []
        ))
        #expect(vm.state == .idle)
        await vm.load()
        if case .ready(let buckets) = vm.state {
            #expect(buckets.count == 1)
            #expect(buckets[0].entries.map(\.id) == ["txn:t1"])
        } else {
            Issue.record("expected ready, got \(vm.state)")
        }
    }

    @Test @MainActor
    func filterChipNarrowsToMatchingKindOnly() async {
        let vm = makeVM(snapshot: ActivitySnapshot(
            transactions: [tx("t1", daysAgo: 0)],
            recurrings: [recurring("r1", daysAhead: 3)],
            signals: [signal("s1", kind: .anomalousSpend)],
            digests: []
        ))
        await vm.load()
        vm.select(.warnings)
        if case .ready(let buckets) = vm.state {
            let ids = buckets.flatMap(\.entries).map(\.id)
            #expect(ids == ["signal:s1"])
        } else {
            Issue.record("expected ready")
        }
    }

    @Test @MainActor
    func selectingAllRestoresEverything() async {
        let vm = makeVM(snapshot: ActivitySnapshot(
            transactions: [tx("t1", daysAgo: 0), tx("t2", daysAgo: 1)],
            recurrings: [],
            signals: [],
            digests: []
        ))
        await vm.load()
        vm.select(.bills)
        vm.select(.all)
        if case .ready(let buckets) = vm.state {
            let ids = buckets.flatMap(\.entries).map(\.id)
            #expect(ids == ["txn:t1", "txn:t2"])
        } else {
            Issue.record("expected ready")
        }
    }

    @Test @MainActor
    func routeForTransactionEmitsOpenTransaction() {
        let entry = LifeEntry(
            id: "txn:abc",
            timestamp: Date(),
            kind: .transaction,
            text: "Cafe",
            metadata: ["txnId": "abc", "category": "food"]
        )
        #expect(ActivityViewModel.route(for: entry) == .openTransaction(id: "abc"))
    }

    @Test @MainActor
    func routeForRecurringBillEmitsOpenRecurring() {
        let entry = LifeEntry(
            id: "bill:r1",
            timestamp: Date(),
            kind: .bill,
            text: "Netflix",
            metadata: ["recurringId": "r1"]
        )
        #expect(ActivityViewModel.route(for: entry) == .openRecurring(id: "r1"))
    }

    @Test @MainActor
    func routeForWarningWithSubjectEmitsOpenTransaction() {
        let entry = LifeEntry(
            id: "signal:s1",
            timestamp: Date(),
            kind: .warning,
            text: "spike",
            metadata: ["subjectId": "txn-xyz", "signalKind": "anomalousSpend"]
        )
        #expect(ActivityViewModel.route(for: entry) == .openTransaction(id: "txn-xyz"))
    }

    @Test @MainActor
    func routeForInsightFallsThroughToInbox() {
        let entry = LifeEntry(
            id: "signal:s2",
            timestamp: Date(),
            kind: .insight,
            text: "new recurring",
            metadata: nil
        )
        #expect(ActivityViewModel.route(for: entry) == .openInbox)
    }
}

// MARK: - test helper

private struct ClosureActivitySource: ActivitySource {
    let snapshot: ActivitySnapshot
    func snapshot(now: Date) async -> ActivitySnapshot { snapshot }
}
