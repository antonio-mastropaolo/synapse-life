import Foundation
import Testing
import SwiftData
@testable import Persistence
@testable import Models

/// Bulk + range query coverage for `TransactionStore`. The Phase 2 Plaid
/// sync upserts 100s of rows per delta and the Phase 3 LLM tool-call
/// `getTransactions(query:)` reads via `between(_:and:category:)` — both
/// surfaces have to be exercised here.
@Suite("TransactionStore")
struct TransactionStoreTests {

    private func makeStore() throws -> TransactionStore {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return TransactionStore(modelContainer: container)
    }

    /// 1000 deterministic transactions spanning 6 months, with categories
    /// striped across "Dining" and "Groceries" so a category filter has
    /// something to match against.
    private func makeTransactions(count: Int) -> [Transaction] {
        let base = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        let day: TimeInterval = 86_400
        // 6 months ~= 183 days; spread `count` rows over that window so
        // the `between` query has multiple buckets to filter through.
        let windowDays = 183.0
        var rows: [Transaction] = []
        rows.reserveCapacity(count)
        for i in 0..<count {
            let offset = Double(i) / Double(count) * windowDays
            let date = base.addingTimeInterval(offset * day)
            let category: TransactionCategory = (i % 2 == 0) ? .knownCategory("Dining") : .knownCategory("Groceries")
            rows.append(Transaction(
                id: "txn-\(i)",
                accountId: "acc-1",
                accountName: "Checking",
                amount: Decimal(-(i % 50 + 1)),
                currency: "USD",
                date: date,
                name: "Merchant \(i)",
                merchantName: "Merchant \(i)",
                category: category,
                subcategory: nil,
                pending: false
            ))
        }
        return rows
    }

    @Test
    func bulkUpsertCountAndNewestLimit() async throws {
        let store = try makeStore()
        let txns = makeTransactions(count: 1000)
        let changed = try await store.upsertAll(txns)
        #expect(changed == 1000)
        #expect(try await store.count() == 1000)

        // `all(limit: 10)` returns the 10 newest by date desc. We generated
        // dates monotonically increasing with i, so the highest indices are
        // the newest.
        let newest10 = try await store.all(limit: 10)
        #expect(newest10.count == 10)
        // The newest row should be the last-generated id.
        #expect(newest10.first?.id == "txn-999")
        // And the dates should be strictly non-increasing.
        let dates = newest10.map(\.date)
        let sorted = dates.sorted(by: >)
        #expect(dates == sorted)
    }

    @Test
    func betweenFiltersByDateAndCategory() async throws {
        let store = try makeStore()
        let txns = makeTransactions(count: 1000)
        _ = try await store.upsertAll(txns)

        // Pick a 30-day slice in the middle of the window.
        let start = Date(timeIntervalSince1970: 1_700_000_000 + 60 * 86_400)
        let end = start.addingTimeInterval(30 * 86_400)
        let diningOnly = try await store.between(start, and: end, category: "Dining")

        // All returned rows must be in range AND in the "Dining" bucket.
        #expect(!diningOnly.isEmpty)
        for txn in diningOnly {
            #expect(txn.date >= start)
            #expect(txn.date < end)
            #expect(txn.category == .knownCategory("Dining"))
        }

        // Sanity: same window without a category filter should be ~2x larger
        // (Dining + Groceries striping).
        let allInWindow = try await store.between(start, and: end)
        #expect(allInWindow.count >= diningOnly.count)
        #expect(allInWindow.count <= diningOnly.count * 2 + 2) // allow striping rounding
    }

    @Test
    func deleteByIdsRemovesRows() async throws {
        let store = try makeStore()
        _ = try await store.upsertAll(makeTransactions(count: 50))
        let victimIds = (0..<10).map { "txn-\($0)" }
        try await store.delete(ids: victimIds)
        #expect(try await store.count() == 40)
        // Removed rows are gone.
        for id in victimIds {
            #expect(try await store.get(id: id) == nil)
        }
    }

    @Test
    func seedIfEmptyReturnsZeroWhenStoreNonEmpty() async throws {
        let store = try makeStore()
        // Pre-populate so the seeder should bail.
        _ = try await store.upsertAll(makeTransactions(count: 3))
        let seeded = try await store.seedIfEmpty {
            // This closure should NOT be invoked once the store is non-empty,
            // but even if the implementation changes to always invoke and
            // then no-op, the test still passes on the return value.
            []
        }
        #expect(seeded == 0)
        #expect(try await store.count() == 3)
    }
}
