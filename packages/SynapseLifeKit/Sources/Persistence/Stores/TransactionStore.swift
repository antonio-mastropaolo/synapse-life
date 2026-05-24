import Foundation
import SwiftData
import Models

/// `ModelActor`-backed store for `PersistedTransaction`. The Phase 3 LLM
/// tool-calls (`getTransactions(query:)`) read from this store; the
/// Phase 2 Plaid sync writes into it.
///
/// All public methods take and return Sendable DTOs (`Transaction`).
@ModelActor
public actor TransactionStore {

    // MARK: - Mutation

    /// Insert or update a single transaction by id. Returns `true` when
    /// the row was new OR when an existing row had at least one field
    /// change.
    @discardableResult
    public func upsert(_ dto: Transaction, syncedAt: Date = Date()) throws -> Bool {
        if let existing = try fetchPersisted(id: dto.id) {
            let changed = existing.update(from: dto, syncedAt: syncedAt)
            try modelContext.save()
            return changed
        }
        modelContext.insert(PersistedTransaction.from(dto, syncedAt: syncedAt))
        try modelContext.save()
        return true
    }

    /// Bulk upsert. Used by the Plaid `/transactions/sync` delta apply.
    /// Returns the number of rows that were new or had a field change.
    @discardableResult
    public func upsertAll(_ dtos: [Transaction], syncedAt: Date = Date()) throws -> Int {
        var changed = 0
        for dto in dtos {
            if let existing = try fetchPersisted(id: dto.id) {
                if existing.update(from: dto, syncedAt: syncedAt) {
                    changed += 1
                }
            } else {
                modelContext.insert(PersistedTransaction.from(dto, syncedAt: syncedAt))
                changed += 1
            }
        }
        try modelContext.save()
        return changed
    }

    /// Delete a set of transactions by id (Plaid sync "removed" array).
    public func delete(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let predicate = #Predicate<PersistedTransaction> { ids.contains($0.id) }
        try modelContext.delete(model: PersistedTransaction.self, where: predicate)
        try modelContext.save()
    }

    /// Delete every transaction row. Used by sign-out.
    public func deleteAll() throws {
        try modelContext.delete(model: PersistedTransaction.self)
        try modelContext.save()
    }

    // MARK: - Read

    /// All transactions, newest first.
    public func all(limit: Int? = nil) throws -> [Transaction] {
        var descriptor = FetchDescriptor<PersistedTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    /// Transactions for a specific account, newest first.
    public func forAccount(_ accountId: String, limit: Int? = nil) throws -> [Transaction] {
        var descriptor = FetchDescriptor<PersistedTransaction>(
            predicate: #Predicate { $0.accountId == accountId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    /// Date-range query. The Phase 3 LLM tool-call `getTransactions(query:)`
    /// uses this to answer "April 2026 dining" style asks.
    public func between(
        _ start: Date,
        and end: Date,
        category: String? = nil,
        limit: Int? = nil
    ) throws -> [Transaction] {
        var descriptor = FetchDescriptor<PersistedTransaction>(
            predicate: #Predicate { row in
                row.date >= start && row.date < end &&
                (category == nil || row.categoryRaw == category)
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    public func get(id: String) throws -> Transaction? {
        try fetchPersisted(id: id)?.toDTO()
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<PersistedTransaction>())
    }

    // MARK: - Seeding (cockpit demo-data path)

    /// One-shot seeder: invokes `seed()` only when the store is empty.
    /// This is the seam the shell uses to lift `DemoData.swift` into the
    /// persistent store on first launch without overwriting a real sync.
    public func seedIfEmpty(_ seed: @Sendable () -> [Transaction]) throws -> Int {
        guard try count() == 0 else { return 0 }
        let dtos = seed()
        for dto in dtos {
            modelContext.insert(PersistedTransaction.from(dto))
        }
        try modelContext.save()
        return dtos.count
    }

    // MARK: - Internal helpers

    private func fetchPersisted(id: String) throws -> PersistedTransaction? {
        var descriptor = FetchDescriptor<PersistedTransaction>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
