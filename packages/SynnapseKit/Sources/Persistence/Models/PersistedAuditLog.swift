import Foundation
import SwiftData

/// Append-only audit log row. Every PII read, every LLM call, every
/// money-movement attempt writes one of these. Surfaced by Settings →
/// "Activity" so the user can see what touched their data, and required
/// for any future SOC2 audit trail.
@Model
public final class PersistedAuditLog {

    /// Synthetic UUID — rows are immutable and never updated, so a separate
    /// id from `(timestamp, kind, subject)` lets us delete by lifetime
    /// retention rules without depending on a composite key.
    @Attribute(.unique) public var id: String

    /// Wall-clock instant the event was recorded.
    public var timestamp: Date

    /// `AuditEventKind.rawValue`. Stored as a raw string so unknown future
    /// kinds round-trip without breaking older clients.
    public var kindRaw: String

    /// What the event acted on, in a UI-readable phrase.
    /// E.g. "transaction:txn_abc", "account:acc_xyz", "llm:ask",
    /// "plaid:link.exchange".
    public var subject: String

    /// Optional one-line context. Never contains a PAN, balance, or full
    /// merchant string in cleartext when `kind` is an LLM call — the
    /// `PIIRedactor` (Phase 3) is responsible for stripping those before
    /// they land here.
    public var detail: String?

    /// Outcome stripe: "ok", "denied", "error", "cancelled". Reported as a
    /// raw string for forward compatibility.
    public var outcome: String

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kindRaw: String,
        subject: String,
        detail: String?,
        outcome: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kindRaw = kindRaw
        self.subject = subject
        self.detail = detail
        self.outcome = outcome
    }
}

/// Closed set the app emits today. Stored as `.rawValue` so unknown kinds
/// from a future schema bump still decode.
public enum AuditEventKind: String, Sendable, CaseIterable {
    /// User opened a balance screen or PII-bearing detail row.
    case piiRead = "pii.read"
    /// Plaid Link flow events (open, success, error).
    case plaidLink = "plaid.link"
    /// A transaction-sync delta was applied.
    case transactionSync = "txn.sync"
    /// An LLM (on-device or remote) was invoked.
    case llmCall = "llm.call"
    /// A money-movement intent was created (Phase 5+).
    case moveMoney = "money.move"
    /// Auth events — sign in, sign out, biometric unlock.
    case auth = "auth"
}

public enum AuditOutcome: String, Sendable {
    case ok
    case denied
    case error
    case cancelled
}
