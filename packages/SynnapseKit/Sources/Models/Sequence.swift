import Foundation

/// A cold-email sequence in the M9 native client. Mirrors the server contract
/// at `app/api/sequences/route.ts` and the SQLite row shape at
/// `cold_email_sequences`. The web client surfaces these as rows in a table;
/// the native client surfaces them as a `Table` on macOS and a navigation
/// stack on iOS.
///
/// The native model is deliberately more structured than the wire shape: the
/// server emits a flat row with `touch1_body`, `current_touch`, `subject`
/// alongside per-sequence metadata. We project that into a `Sequence` with
/// a typed `[SequenceStage]` array so the editor view can iterate stages.
/// Today the server only stores a single body (`touch1_body`); the native
/// model carries up to three stages and the live API fills in placeholders
/// for stages 2 and 3 until the server contract grows.
public struct Sequence: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let opportunityId: String
    public let leadEmail: String
    public let leadDisplay: String
    public let subject: String
    public let stages: [SequenceStage]
    public let currentTouch: Int
    public let lastSentAt: Date?
    public let nextDueAt: Date?
    public let status: SequenceStatus
    public let lastLog: String?
    public let createdAt: Date

    public init(
        id: String,
        opportunityId: String,
        leadEmail: String,
        leadDisplay: String,
        subject: String,
        stages: [SequenceStage],
        currentTouch: Int,
        lastSentAt: Date?,
        nextDueAt: Date?,
        status: SequenceStatus,
        lastLog: String?,
        createdAt: Date
    ) {
        self.id = id
        self.opportunityId = opportunityId
        self.leadEmail = leadEmail
        self.leadDisplay = leadDisplay
        self.subject = subject
        self.stages = stages
        self.currentTouch = currentTouch
        self.lastSentAt = lastSentAt
        self.nextDueAt = nextDueAt
        self.status = status
        self.lastLog = lastLog
        self.createdAt = createdAt
    }

    /// Convenience: the stage currently being executed (or the first stage
    /// if the sequence has not started yet). Returns nil only when the
    /// sequence has no stages at all (degenerate server data).
    public var activeStage: SequenceStage? {
        if stages.isEmpty { return nil }
        let clamped = max(1, min(currentTouch, stages.count))
        return stages.first { $0.touchNumber == clamped } ?? stages.first
    }
}

/// One stage in a sequence. `touchNumber` is 1-indexed to match the server's
/// `current_touch` semantics. `dayOffset` is days after enrollment (touch 1 =
/// 0 by convention).
public struct SequenceStage: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let touchNumber: Int
    public let dayOffset: Int
    public let channel: SequenceChannel
    public let subject: String
    public let body: String
    public let status: SequenceStageStatus

    public init(
        id: String,
        touchNumber: Int,
        dayOffset: Int,
        channel: SequenceChannel,
        subject: String,
        body: String,
        status: SequenceStageStatus
    ) {
        self.id = id
        self.touchNumber = touchNumber
        self.dayOffset = dayOffset
        self.channel = channel
        self.subject = subject
        self.body = body
        self.status = status
    }
}

/// Channel for a stage. The server only models email today; the enum is
/// forward-compatible so when LinkedIn / SMS land we can decode them
/// without a schema break.
public enum SequenceChannel: String, Codable, Sendable, Hashable, CaseIterable {
    case email
    case linkedin
    case sms
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SequenceChannel(rawValue: raw) ?? .unknown
    }
}

/// Per-stage status. `draft` is local-only — the server has not seen the
/// edit yet. `queued` and `sent` are server states. `skipped` covers the
/// "operator paused the sequence after this stage" case.
public enum SequenceStageStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case draft
    case queued
    case sent
    case skipped
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SequenceStageStatus(rawValue: raw) ?? .unknown
    }
}

/// Forward-compat status enum. Server today emits
/// `active | paused | replied | completed`; any unknown string maps to
/// `.unknown` instead of throwing.
public enum SequenceStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case active
    case paused
    case replied
    case completed
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SequenceStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - Server wire shape

/// Wire-level row from `GET /api/sequences`. The web client decodes this
/// directly; the native client projects it into `Sequence` via
/// `Sequence.fromServerRow(_:)`.
///
/// All timestamps are unix seconds. `touch1_body` is the only body stored
/// server-side today — stages 2 and 3 are surfaced as empty drafts so the
/// editor can fill them in without a separate fetch.
public struct ServerSequenceRow: Decodable, Sendable {
    public let id: String
    public let opportunity_id: String
    public let lead_email: String
    public let lead_display: String
    public let subject: String
    public let touch1_body: String
    public let current_touch: Int
    public let last_sent_at: Double?
    public let next_due_at: Double?
    public let status: String
    public let last_log: String?
    public let created_at: Double
}

public struct ServerSequencesListResponse: Decodable, Sendable {
    public let total: Int
    public let sequences: [ServerSequenceRow]
}

extension Sequence {
    /// Project a server row into the native `Sequence`. Synthesises stages
    /// 2 and 3 as empty drafts — the server only persists `touch1_body`
    /// today, but the editor still needs a stable shape to bind against.
    public static func fromServerRow(_ row: ServerSequenceRow) -> Sequence {
        let status = SequenceStatus(rawValue: row.status) ?? .unknown
        let lastSent = row.last_sent_at.map { Date(timeIntervalSince1970: $0) }
        let nextDue = row.next_due_at.map { Date(timeIntervalSince1970: $0) }
        let created = Date(timeIntervalSince1970: row.created_at)

        let stages: [SequenceStage] = [
            SequenceStage(
                id: "\(row.id)#1",
                touchNumber: 1,
                dayOffset: 0,
                channel: .email,
                subject: row.subject,
                body: row.touch1_body,
                status: row.current_touch >= 1 ? .sent : .queued
            ),
            SequenceStage(
                id: "\(row.id)#2",
                touchNumber: 2,
                dayOffset: 3,
                channel: .email,
                subject: "",
                body: "",
                status: row.current_touch >= 2 ? .sent : .draft
            ),
            SequenceStage(
                id: "\(row.id)#3",
                touchNumber: 3,
                dayOffset: 7,
                channel: .email,
                subject: "",
                body: "",
                status: row.current_touch >= 3 ? .sent : .draft
            )
        ]

        return Sequence(
            id: row.id,
            opportunityId: row.opportunity_id,
            leadEmail: row.lead_email,
            leadDisplay: row.lead_display,
            subject: row.subject,
            stages: stages,
            currentTouch: row.current_touch,
            lastSentAt: lastSent,
            nextDueAt: nextDue,
            status: status,
            lastLog: row.last_log,
            createdAt: created
        )
    }
}
