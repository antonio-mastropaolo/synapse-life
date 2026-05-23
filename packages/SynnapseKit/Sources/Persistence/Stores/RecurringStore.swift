import Foundation
import SwiftData
import Models

/// `ModelActor`-backed store for detected recurring charges. The detector in
/// `Features/Recurrings` produces `Recurring` DTOs with stable ids; this store
/// upserts them so a re-derivation refreshes wording (amount drift, a fresh
/// `predictedNext`) without duplicating a merchant's row. All methods take /
/// return Sendable DTOs — the `@Model` reference type never crosses the actor
/// boundary.
@ModelActor
public actor RecurringStore {

    /// Insert or content-update one recurring. Returns `true` when the row is
    /// new or any surfaced field changed.
    @discardableResult
    public func upsert(_ dto: Recurring, syncedAt: Date = Date()) throws -> Bool {
        if let existing = try fetchPersisted(id: dto.id) {
            let changed = existing.update(from: dto, syncedAt: syncedAt)
            try modelContext.save()
            return changed
        }
        modelContext.insert(PersistedRecurring.from(dto, syncedAt: syncedAt))
        try modelContext.save()
        return true
    }

    /// Bulk upsert. Returns the count of rows that were new or changed.
    @discardableResult
    public func upsertAll(_ dtos: [Recurring], syncedAt: Date = Date()) throws -> Int {
        var changed = 0
        for dto in dtos {
            if let existing = try fetchPersisted(id: dto.id) {
                if existing.update(from: dto, syncedAt: syncedAt) { changed += 1 }
            } else {
                modelContext.insert(PersistedRecurring.from(dto, syncedAt: syncedAt))
                changed += 1
            }
        }
        try modelContext.save()
        return changed
    }

    /// All recurrings, soonest predicted charge first (then merchant, then id
    /// for stable ordering). Mirrors the detector's own ordering so callers can
    /// use the slice directly as a "next up" view.
    public func all() throws -> [Recurring] {
        let descriptor = FetchDescriptor<PersistedRecurring>(
            sortBy: [
                SortDescriptor(\.predictedNext, order: .forward),
                SortDescriptor(\.merchant, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    /// Recurrings whose next charge falls within `days` of `now` (inclusive of
    /// `now`, exclusive of the far edge). Drives the "upcoming bills" feed.
    public func upcoming(within days: Int, now: Date = Date()) throws -> [Recurring] {
        let horizon = now.addingTimeInterval(Double(days) * 86_400)
        let descriptor = FetchDescriptor<PersistedRecurring>(
            predicate: #Predicate { $0.predictedNext >= now && $0.predictedNext < horizon },
            sortBy: [
                SortDescriptor(\.predictedNext, order: .forward),
                SortDescriptor(\.merchant, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    public func get(id: String) throws -> Recurring? {
        try fetchPersisted(id: id)?.toDTO()
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<PersistedRecurring>())
    }

    public func deleteAll() throws {
        try modelContext.delete(model: PersistedRecurring.self)
        try modelContext.save()
    }

    private func fetchPersisted(id: String) throws -> PersistedRecurring? {
        var descriptor = FetchDescriptor<PersistedRecurring>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
