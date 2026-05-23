import Foundation
import SwiftData
import Models

/// `ModelActor`-backed store for `PersistedFinanceAccount`.
///
/// All public methods take and return Sendable DTOs (`FinanceAccount`); the
/// `@Model` reference type never crosses the actor boundary. The Phase 2
/// `PlaidTransactionsSync` actor talks to this store via `upsert(_:)`.
@ModelActor
public actor AccountStore {

    /// Insert or update a single account by id. Returns `true` when the row
    /// was new OR when an existing row had at least one field change. The
    /// transaction is saved synchronously.
    @discardableResult
    public func upsert(_ dto: FinanceAccount, syncedAt: Date = Date()) throws -> Bool {
        if let existing = try fetchPersisted(id: dto.id) {
            let changed = existing.update(from: dto, syncedAt: syncedAt)
            try modelContext.save()
            return changed
        }
        let new = PersistedFinanceAccount.from(dto, syncedAt: syncedAt)
        modelContext.insert(new)
        try modelContext.save()
        return true
    }

    /// Bulk upsert. Returns the number of rows that were new or changed.
    @discardableResult
    public func upsertAll(_ dtos: [FinanceAccount], syncedAt: Date = Date()) throws -> Int {
        var changed = 0
        for dto in dtos {
            if let existing = try fetchPersisted(id: dto.id) {
                if existing.update(from: dto, syncedAt: syncedAt) {
                    changed += 1
                }
            } else {
                modelContext.insert(PersistedFinanceAccount.from(dto, syncedAt: syncedAt))
                changed += 1
            }
        }
        try modelContext.save()
        return changed
    }

    /// Fetch all accounts as DTOs, optionally filtered by institution id.
    public func all(institutionId: String? = nil) throws -> [FinanceAccount] {
        var descriptor = FetchDescriptor<PersistedFinanceAccount>(
            sortBy: [SortDescriptor(\.name)]
        )
        if let inst = institutionId {
            descriptor.predicate = #Predicate<PersistedFinanceAccount> { row in
                row.institutionId == inst
            }
        }
        let rows = try modelContext.fetch(descriptor)
        return rows.map { $0.toDTO() }
    }

    /// Fetch a single account by id, projected to a DTO.
    public func get(id: String) throws -> FinanceAccount? {
        try fetchPersisted(id: id)?.toDTO()
    }

    /// Total row count — used by `seedIfEmpty(...)` and by the staleness
    /// banner heuristic.
    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<PersistedFinanceAccount>())
    }

    /// Delete every account row. Used by the "Reset" diagnostic and by
    /// sign-out (Phase 5 hooks it).
    public func deleteAll() throws {
        try modelContext.delete(model: PersistedFinanceAccount.self)
        try modelContext.save()
    }

    // MARK: - Internal helpers (do not expose @Model across the actor)

    private func fetchPersisted(id: String) throws -> PersistedFinanceAccount? {
        var descriptor = FetchDescriptor<PersistedFinanceAccount>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
