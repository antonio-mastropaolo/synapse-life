import Foundation

/// One message in the unified inbox. Mirrors `/api/messages` (and the
/// underlying Drizzle `messages` table) on the Synapse v2 server.
///
/// The `isRead` flag is a CLIENT-side projection — the server has no
/// `read` column today. Optimistic mark-read flows in [[InboxListViewModel]]
/// drive this flag locally and POST a `PATCH /api/messages/:id` request that
/// the server can wire up later (forward-compat seam). Equality + hashing are
/// id-only so the same logical message with a flipped `isRead` is still the
/// same row.
public struct InboxItem: Sendable, Identifiable, Hashable {
    public let id: String
    public let source: Source
    public let threadId: String?
    public let sender: String
    public let senderDisplay: String
    public let subject: String?
    public let body: String
    public let bodyPreview: String
    public let receivedAt: Date
    public var isRead: Bool

    public init(
        id: String,
        source: Source,
        threadId: String?,
        sender: String,
        senderDisplay: String,
        subject: String?,
        body: String,
        bodyPreview: String,
        receivedAt: Date,
        isRead: Bool
    ) {
        self.id = id
        self.source = source
        self.threadId = threadId
        self.sender = sender
        self.senderDisplay = senderDisplay
        self.subject = subject
        self.body = body
        self.bodyPreview = bodyPreview
        self.receivedAt = receivedAt
        self.isRead = isRead
    }

    public static func == (lhs: InboxItem, rhs: InboxItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// What the list row + detail header show as the subject. Falls back to
    /// the body preview when the subject is missing (common for Slack DMs,
    /// SMS, and some Outlook variants).
    public var displaySubject: String {
        if let subject, !subject.isEmpty { return subject }
        return bodyPreview
    }
}

extension InboxItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, source, threadId
        case sender, senderDisplay
        case subject, body, bodyPreview
        case receivedAt
        case isRead, read
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        let rawSource = try c.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        self.source = Source(rawValue: rawSource) ?? .unknown
        self.threadId = try c.decodeIfPresent(String.self, forKey: .threadId)
        self.sender = try c.decode(String.self, forKey: .sender)
        self.senderDisplay = try c.decode(String.self, forKey: .senderDisplay)
        self.subject = try c.decodeIfPresent(String.self, forKey: .subject)
        self.body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        if let preview = try c.decodeIfPresent(String.self, forKey: .bodyPreview) {
            self.bodyPreview = preview
        } else {
            // Compute a one-line preview from the body; cap at 140 chars so
            // the row view doesn't paginate the body.
            let collapsed = self.body
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            self.bodyPreview = String(collapsed.prefix(140))
        }
        self.receivedAt = try c.decode(Date.self, forKey: .receivedAt)
        // Read flag is forward-compat: server may emit `isRead` or `read`,
        // and we default to false (unread) when absent.
        if let isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) {
            self.isRead = isRead
        } else {
            self.isRead = try c.decodeIfPresent(Bool.self, forKey: .read) ?? false
        }
    }
}

/// Page envelope mirroring `/api/messages` response shape. `total` is the
/// server's full count (used for hint UI); `items` are the rows on this page.
public struct InboxPage: Sendable, Decodable, Equatable {
    public let total: Int
    public let items: [InboxItem]
    public let nextCursor: String?

    public init(total: Int, items: [InboxItem], nextCursor: String? = nil) {
        self.total = total
        self.items = items
        self.nextCursor = nextCursor
    }

    private enum CodingKeys: String, CodingKey {
        case total, items, messages, nextCursor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try c.decode(Int.self, forKey: .total)
        // The route emits `messages: []` today; reserve `items` for future
        // pagination shapes.
        if let items = try c.decodeIfPresent([InboxItem].self, forKey: .items) {
            self.items = items
        } else {
            self.items = try c.decodeIfPresent([InboxItem].self, forKey: .messages) ?? []
        }
        self.nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

/// Folder filter for the macOS three-column layout. Each folder maps to a
/// single `Source`; the `.all` case is represented client-side by `nil`
/// (so the existence of `SourceFolder` itself is the "named source" set).
public enum SourceFolder: String, CaseIterable, Sendable, Hashable {
    case gmail
    case calendar
    case slack
    case outlook
    case discord
    case pipeline

    public var source: Source {
        switch self {
        case .gmail: return .gmail
        case .calendar: return .calendar
        case .slack: return .slack
        case .outlook: return .outlook
        case .discord: return .discord
        case .pipeline: return .pipeline
        }
    }

    public var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .calendar: return "Calendar"
        case .slack: return "Slack"
        case .outlook: return "Outlook"
        case .discord: return "Discord"
        case .pipeline: return "Pipeline"
        }
    }

    public init?(source: Source) {
        guard let f = SourceFolder.allCases.first(where: { $0.source == source }) else {
            return nil
        }
        self = f
    }
}

// MARK: - Decoding helper

extension JSONDecoder {
    /// Decoder for `/api/messages` payloads. The route emits ISO-8601 with
    /// fractional seconds on `receivedAt` / `createdAt`; we use the same
    /// fallback strategy as `synnapseSpotlight` so plain ISO-8601 timestamps
    /// also decode.
    public static let synnapseInbox: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFraction.date(from: raw) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable ISO-8601 date: \(raw)"
            )
        }
        return dec
    }()
}
