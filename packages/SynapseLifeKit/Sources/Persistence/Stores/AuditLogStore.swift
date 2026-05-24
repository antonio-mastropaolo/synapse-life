import Foundation
import SwiftData

/// Append-only audit log. Every entry is a `PersistedAuditLog` row written
/// once and never updated. Surfaced in Settings → Activity; queried by the
/// future SOC2 retention worker.
///
/// PII redaction is the caller's responsibility — by the time a row lands
/// here, `detail` must already be redacted (Phase 3's `PIIRedactor`).
@ModelActor
public actor AuditLogStore {

    /// Append one event. The id is synthesised; the timestamp defaults to
    /// `now` so callers don't have to thread a clock.
    public func append(
        kind: AuditEventKind,
        subject: String,
        detail: String? = nil,
        outcome: AuditOutcome = .ok,
        timestamp: Date = Date()
    ) throws {
        let row = PersistedAuditLog(
            timestamp: timestamp,
            kindRaw: kind.rawValue,
            subject: subject,
            detail: detail,
            outcome: outcome.rawValue
        )
        modelContext.insert(row)
        try modelContext.save()
    }

    /// Recent events, newest first. The Settings → Activity row uses this
    /// with `limit: 200`.
    public func recent(limit: Int = 200) throws -> [AuditLogEntry] {
        var descriptor = FetchDescriptor<PersistedAuditLog>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { row in
            AuditLogEntry(
                id: row.id,
                timestamp: row.timestamp,
                kind: AuditEventKind(rawValue: row.kindRaw),
                kindRaw: row.kindRaw,
                subject: row.subject,
                detail: row.detail,
                outcome: AuditOutcome(rawValue: row.outcome),
                outcomeRaw: row.outcome
            )
        }
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<PersistedAuditLog>())
    }

    /// Trim rows older than `retentionDays` days. Called nightly by the
    /// Phase 4 background-refresh task.
    public func prune(olderThan retentionDays: Int = 365, now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 3600)
        let predicate = #Predicate<PersistedAuditLog> { $0.timestamp < cutoff }
        try modelContext.delete(model: PersistedAuditLog.self, where: predicate)
        try modelContext.save()
    }
}

/// Sendable projection used to cross the actor boundary. `kind` is `nil`
/// when the stored raw string is unknown to this binary (forward-compat
/// with a future schema bump).
public struct AuditLogEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let kind: AuditEventKind?
    public let kindRaw: String
    public let subject: String
    public let detail: String?
    public let outcome: AuditOutcome?
    public let outcomeRaw: String

    public init(
        id: String,
        timestamp: Date,
        kind: AuditEventKind?,
        kindRaw: String,
        subject: String,
        detail: String?,
        outcome: AuditOutcome?,
        outcomeRaw: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.kindRaw = kindRaw
        self.subject = subject
        self.detail = detail
        self.outcome = outcome
        self.outcomeRaw = outcomeRaw
    }
}
