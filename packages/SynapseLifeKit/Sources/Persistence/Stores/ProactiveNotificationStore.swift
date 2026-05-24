import Foundation
import SwiftData
import Models

/// `ModelActor`-backed store for the proactive feed. The analyzer produces
/// `ProactiveSignal`s with stable ids; this store upserts them so a re-run
/// refreshes wording without resurrecting dismissed items or duplicating
/// rows. All methods take / return Sendable DTOs — the `@Model` reference
/// type never crosses the actor boundary.
@ModelActor
public actor ProactiveNotificationStore {

    /// Insert or content-update one signal. Returns `true` when the row is new
    /// or any surfaced field changed (the caller uses this to decide whether
    /// to fire a fresh local notification).
    @discardableResult
    public func upsert(_ signal: ProactiveSignal, createdAt: Date = Date()) throws -> Bool {
        if let existing = try fetchPersisted(id: signal.id) {
            let changed = existing.update(from: signal)
            try modelContext.save()
            return changed
        }
        modelContext.insert(PersistedNotification.from(signal, createdAt: createdAt))
        try modelContext.save()
        return true
    }

    /// Bulk upsert. Returns the count of rows that were new or changed.
    @discardableResult
    public func upsertAll(_ signals: [ProactiveSignal], createdAt: Date = Date()) throws -> Int {
        var changed = 0
        for signal in signals {
            if let existing = try fetchPersisted(id: signal.id) {
                if existing.update(from: signal) { changed += 1 }
            } else {
                modelContext.insert(PersistedNotification.from(signal, createdAt: createdAt))
                changed += 1
            }
        }
        try modelContext.save()
        return changed
    }

    /// Inbox feed, urgency-first (`alert` > `warning` > `info`), then most
    /// recent. Dismissed rows are hidden unless `includeDismissed` is set.
    public func recent(includeDismissed: Bool = false, limit: Int? = nil) throws -> [ProactiveSignal] {
        var descriptor = FetchDescriptor<PersistedNotification>(
            sortBy: [
                SortDescriptor(\.severityRank, order: .reverse),
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.id),
            ]
        )
        if !includeDismissed {
            descriptor.predicate = #Predicate<PersistedNotification> { $0.dismissed == false }
        }
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    public func get(id: String) throws -> ProactiveSignal? {
        try fetchPersisted(id: id)?.toDTO()
    }

    /// Set the dismissed flag for one row. Returns `true` if a matching row
    /// was found and updated.
    @discardableResult
    public func setDismissed(id: String, _ dismissed: Bool) throws -> Bool {
        guard let row = try fetchPersisted(id: id) else { return false }
        row.dismissed = dismissed
        try modelContext.save()
        return true
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<PersistedNotification>())
    }

    public func deleteAll() throws {
        try modelContext.delete(model: PersistedNotification.self)
        try modelContext.save()
    }

    /// Drop rows first persisted more than `retentionDays` ago. Called by the
    /// nightly background-refresh task alongside the analyzer pass.
    public func prune(olderThan retentionDays: Int = 90, now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 3600)
        let predicate = #Predicate<PersistedNotification> { $0.createdAt < cutoff }
        try modelContext.delete(model: PersistedNotification.self, where: predicate)
        try modelContext.save()
    }

    private func fetchPersisted(id: String) throws -> PersistedNotification? {
        var descriptor = FetchDescriptor<PersistedNotification>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
