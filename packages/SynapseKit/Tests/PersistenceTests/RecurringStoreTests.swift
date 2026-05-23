import Foundation
import Testing
@testable import Persistence
@testable import Models

/// G3 — durable recurring-charge store. `RecurringStore` mirrors `Recurring`
/// so a periodic re-derivation dedups against persisted rows and the agent's
/// `get_recurrings` tool can answer from the store. These tests pin the
/// round-trip (including exact `Decimal`), the dedup changed-flag, the
/// soonest-first ordering, the upcoming-window filter, and bulk count.
@Suite("RecurringStore")
struct RecurringStoreTests {

    static let now = Date(timeIntervalSince1970: 1_779_840_000)

    private func makeStore() throws -> RecurringStore {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return RecurringStore(modelContainer: container)
    }

    private func recurring(
        id: String,
        merchant: String = "Acme",
        category: String = "subscriptions",
        medianAmount: Decimal = Decimal(string: "12.99")!,
        cadenceDays: Int = 30,
        predictedNext: Date = RecurringStoreTests.now,
        confidence: Double = 0.9,
        isIncome: Bool = false
    ) -> Recurring {
        Recurring(
            id: id,
            merchant: merchant,
            category: category,
            medianAmount: medianAmount,
            cadenceDays: cadenceDays,
            lastSeen: predictedNext.addingTimeInterval(-Double(cadenceDays) * 86_400),
            predictedNext: predictedNext,
            occurrenceCount: 4,
            confidence: confidence,
            transactionIds: ["t1", "t2", "t3", "t4"],
            isIncome: isIncome
        )
    }

    @Test
    func upsertRoundTripsAllFieldsWithExactDecimal() async throws {
        let store = try makeStore()
        let r = recurring(id: "r1", merchant: "Netflix", medianAmount: Decimal(string: "15.49")!)
        _ = try await store.upsert(r, syncedAt: Self.now)

        let read = try #require(try await store.get(id: "r1"))
        #expect(read.id == "r1")
        #expect(read.merchant == "Netflix")
        #expect(read.category == "subscriptions")
        #expect(read.medianAmount == Decimal(string: "15.49")!)
        #expect(read.cadenceDays == 30)
        #expect(read.occurrenceCount == 4)
        #expect(read.transactionIds == ["t1", "t2", "t3", "t4"])
        #expect(read.isIncome == false)
    }

    @Test
    func reUpsertReportsChangedOnlyWhenContentDiffers() async throws {
        let store = try makeStore()
        _ = try await store.upsert(recurring(id: "r1", medianAmount: Decimal(string: "9.99")!), syncedAt: Self.now)

        let unchanged = try await store.upsert(recurring(id: "r1", medianAmount: Decimal(string: "9.99")!), syncedAt: Self.now)
        #expect(unchanged == false)

        let changed = try await store.upsert(recurring(id: "r1", medianAmount: Decimal(string: "11.99")!), syncedAt: Self.now)
        #expect(changed == true)
        #expect(try await store.count() == 1)
    }

    @Test
    func allOrdersBySoonestPredictedNext() async throws {
        let store = try makeStore()
        let soon = Self.now.addingTimeInterval(2 * 86_400)
        let later = Self.now.addingTimeInterval(20 * 86_400)
        _ = try await store.upsert(recurring(id: "late", merchant: "B", predictedNext: later), syncedAt: Self.now)
        _ = try await store.upsert(recurring(id: "soon", merchant: "A", predictedNext: soon), syncedAt: Self.now)

        let all = try await store.all()
        #expect(all.map(\.id) == ["soon", "late"])
    }

    @Test
    func upcomingFiltersToWindow() async throws {
        let store = try makeStore()
        let inWindow = Self.now.addingTimeInterval(3 * 86_400)
        let pastEdge = Self.now.addingTimeInterval(40 * 86_400)
        let alreadyPast = Self.now.addingTimeInterval(-1 * 86_400)
        _ = try await store.upsert(recurring(id: "in", merchant: "A", predictedNext: inWindow), syncedAt: Self.now)
        _ = try await store.upsert(recurring(id: "far", merchant: "B", predictedNext: pastEdge), syncedAt: Self.now)
        _ = try await store.upsert(recurring(id: "past", merchant: "C", predictedNext: alreadyPast), syncedAt: Self.now)

        let upcoming = try await store.upcoming(within: 30, now: Self.now)
        #expect(upcoming.map(\.id) == ["in"])
    }

    @Test
    func upsertAllReturnsNewOrChangedCount() async throws {
        let store = try makeStore()
        let first = try await store.upsertAll([
            recurring(id: "a"), recurring(id: "b"), recurring(id: "c"),
        ], syncedAt: Self.now)
        #expect(first == 3)

        // Re-run: b's amount changes, a+c identical, d is new -> 2 changed.
        let second = try await store.upsertAll([
            recurring(id: "a"),
            recurring(id: "b", medianAmount: Decimal(string: "99.99")!),
            recurring(id: "c"),
            recurring(id: "d"),
        ], syncedAt: Self.now)
        #expect(second == 2)
        #expect(try await store.count() == 4)
    }

    @Test
    func deleteAllClearsStore() async throws {
        let store = try makeStore()
        _ = try await store.upsertAll([recurring(id: "a"), recurring(id: "b")], syncedAt: Self.now)
        try await store.deleteAll()
        #expect(try await store.count() == 0)
    }
}
