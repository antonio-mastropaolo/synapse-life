import Foundation
import SwiftData
import Models

/// `ModelActor`-backed store for `PersistedInvestmentPosition`. The natural
/// key is `(accountId, securityId)`; we project it through the synthesized
/// composite `id` so SwiftData's `.unique` attribute can enforce it.
@ModelActor
public actor InvestmentStore {

    @discardableResult
    public func upsert(_ dto: InvestmentPosition, syncedAt: Date = Date()) throws -> Bool {
        if let existing = try fetchPersisted(id: dto.id) {
            let changed = existing.update(from: dto, syncedAt: syncedAt)
            try modelContext.save()
            return changed
        }
        modelContext.insert(PersistedInvestmentPosition.from(dto, syncedAt: syncedAt))
        try modelContext.save()
        return true
    }

    @discardableResult
    public func upsertAll(_ dtos: [InvestmentPosition], syncedAt: Date = Date()) throws -> Int {
        var changed = 0
        for dto in dtos {
            if let existing = try fetchPersisted(id: dto.id) {
                if existing.update(from: dto, syncedAt: syncedAt) {
                    changed += 1
                }
            } else {
                modelContext.insert(PersistedInvestmentPosition.from(dto, syncedAt: syncedAt))
                changed += 1
            }
        }
        try modelContext.save()
        return changed
    }

    public func all() throws -> [InvestmentPosition] {
        let descriptor = FetchDescriptor<PersistedInvestmentPosition>()
        return Self.byValueDescending(try modelContext.fetch(descriptor).map { $0.toDTO() })
    }

    public func forAccount(_ accountId: String) throws -> [InvestmentPosition] {
        let descriptor = FetchDescriptor<PersistedInvestmentPosition>(
            predicate: #Predicate { $0.accountId == accountId }
        )
        return Self.byValueDescending(try modelContext.fetch(descriptor).map { $0.toDTO() })
    }

    /// `value` is persisted as a decimal String to preserve exactness, so it
    /// can't be a SwiftData `SortDescriptor` key path (those need a stored,
    /// SQL-mappable column, and a String sort would order "9" after "100").
    /// Position counts per portfolio are small, so we sort the projected DTOs
    /// numerically in memory instead.
    private static func byValueDescending(
        _ positions: [InvestmentPosition]
    ) -> [InvestmentPosition] {
        positions.sorted { $0.value > $1.value }
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<PersistedInvestmentPosition>())
    }

    public func deleteAll() throws {
        try modelContext.delete(model: PersistedInvestmentPosition.self)
        try modelContext.save()
    }

    private func fetchPersisted(id: String) throws -> PersistedInvestmentPosition? {
        var descriptor = FetchDescriptor<PersistedInvestmentPosition>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
