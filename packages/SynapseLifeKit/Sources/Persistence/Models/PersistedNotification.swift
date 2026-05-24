import Foundation
import SwiftData
import Models

/// SwiftData mirror of `ProactiveSignal` — one row per proactive insight the
/// analyzer has surfaced. Persisting these is what lets a nightly pass dedup
/// against what the user has already seen (and dismissed) rather than
/// re-notifying about the same bill or anomaly every run.
///
/// `kindRaw` / `severityRaw` are stored as raw strings (projected through the
/// `kind` / `severity` computed properties) so an unknown future kind decodes
/// without trapping. `severityRank` is denormalised as an `Int` so the store
/// can sort by urgency in SQL — a computed key path can't back a
/// `SortDescriptor`. `createdAt` is the persistence instant (distinct from the
/// signal's "about" `date`, which can be in the future for an upcoming bill)
/// so retention pruning has a stable, monotonic key.
@Model
public final class PersistedNotification {

    @Attribute(.unique) public var id: String

    public var kindRaw: String
    public var headline: String
    public var body: String
    public var subjectId: String?

    /// The instant the signal is "about" (predicted charge date / evaluation
    /// time). Used as the secondary sort key after severity.
    public var date: Date

    public var severityRaw: String
    /// Denormalised `ProactiveSignal.Severity.rank` for SQL-side sorting.
    public var severityRank: Int

    /// User dismissed this from the inbox. Survives re-upserts so a nightly
    /// re-run never resurrects a dismissed item.
    public var dismissed: Bool

    /// Wall-clock instant first persisted. Retention pruning keys off this.
    public var createdAt: Date

    public init(
        id: String,
        kindRaw: String,
        headline: String,
        body: String,
        subjectId: String?,
        date: Date,
        severityRaw: String,
        severityRank: Int,
        dismissed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.headline = headline
        self.body = body
        self.subjectId = subjectId
        self.date = date
        self.severityRaw = severityRaw
        self.severityRank = severityRank
        self.dismissed = dismissed
        self.createdAt = createdAt
    }

    /// Projected enum view of `kindRaw`; `nil` on an unrecognised raw string.
    public var kind: ProactiveSignal.Kind? {
        ProactiveSignal.Kind(rawValue: kindRaw)
    }

    /// Projected enum view of `severityRaw`; `nil` on an unrecognised raw
    /// string.
    public var severity: ProactiveSignal.Severity? {
        ProactiveSignal.Severity(rawValue: severityRaw)
    }
}
