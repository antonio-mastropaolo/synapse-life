import Foundation

/// One AI advisor persona surfaced in the macOS sidebar / iOS list. Mirrors
/// the wire shape of synapse-v2's `GET /api/ai-advisors`:
///
/// ```json
/// {
///   "id": "financial",
///   "name": "Wealth Coach",
///   "specialty": "Budgets & cash flow",
///   "avatarColor": "#34d399",
///   "avatarInitials": "WC",
///   "unreadCount": 2,
///   "lastThreadId": "thr_…",
///   "lastSummary": "Reviewed sub renewals…",
///   "lastActiveAt": 1733...000
/// }
/// ```
///
/// Server emits `lastActiveAt` as **milliseconds since epoch**; the custom
/// `Decodable` below normalizes to `Date`. Unknown fields decode as `nil`
/// (forward-compat).
public struct Advisor: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let specialty: String
    public let avatarColorHex: String
    public let avatarInitials: String
    public let unreadCount: Int
    public let lastThreadId: String?
    public let lastSummary: String?
    public let lastActiveAt: Date?

    public init(
        id: String,
        name: String,
        specialty: String,
        avatarColorHex: String,
        avatarInitials: String,
        unreadCount: Int = 0,
        lastThreadId: String? = nil,
        lastSummary: String? = nil,
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.specialty = specialty
        self.avatarColorHex = avatarColorHex
        self.avatarInitials = avatarInitials
        self.unreadCount = unreadCount
        self.lastThreadId = lastThreadId
        self.lastSummary = lastSummary
        self.lastActiveAt = lastActiveAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, specialty
        case avatarColor, avatarColorHex
        case avatarInitials
        case unreadCount
        case lastThreadId
        case lastSummary
        case lastActiveAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.specialty = try c.decode(String.self, forKey: .specialty)
        // Server uses `avatarColor`; we keep an alias for tests that prefer
        // the explicit `avatarColorHex` key.
        if let raw = try c.decodeIfPresent(String.self, forKey: .avatarColor) {
            self.avatarColorHex = raw
        } else {
            self.avatarColorHex = try c.decode(String.self, forKey: .avatarColorHex)
        }
        self.avatarInitials = try c.decode(String.self, forKey: .avatarInitials)
        self.unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        self.lastThreadId = try c.decodeIfPresent(String.self, forKey: .lastThreadId)
        self.lastSummary = try c.decodeIfPresent(String.self, forKey: .lastSummary)
        // Server emits epoch milliseconds for `lastActiveAt`. Tolerate
        // null, seconds-shaped numbers, and ISO-8601 strings as well.
        if let ms = try? c.decode(Int64.self, forKey: .lastActiveAt) {
            self.lastActiveAt = Advisor.dateFromEpoch(ms)
        } else if let s = try? c.decode(Double.self, forKey: .lastActiveAt) {
            self.lastActiveAt = Advisor.dateFromEpoch(Int64(s))
        } else if let iso = try? c.decode(String.self, forKey: .lastActiveAt) {
            self.lastActiveAt = Advisor.parseISO(iso)
        } else {
            self.lastActiveAt = nil
        }
    }

    /// The server emits milliseconds for fresh threads, but a few legacy
    /// rows still carry seconds. We pick the right scale by magnitude:
    /// anything above 10^12 is ms, below is seconds.
    fileprivate static func dateFromEpoch(_ value: Int64) -> Date {
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1000.0)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    fileprivate static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: s)
    }
}

/// Wire envelope for `GET /api/ai-advisors`.
public struct AdvisorsResponse: Decodable, Sendable {
    public let advisors: [Advisor]

    public init(advisors: [Advisor]) {
        self.advisors = advisors
    }
}

// MARK: - Chat message

/// A single message inside an advisor thread. Round-tripped to/from the
/// streaming chat surface — the streaming view model appends an `assistant`
/// message and mutates its `content` as tokens arrive.
public struct ChatMessage: Sendable, Hashable, Identifiable {
    public let id: String
    public let role: MessageRole
    public var content: String
    public let createdAt: Date
    /// When `true`, this message is still receiving stream deltas. The view
    /// uses this to paint a blinking caret at the tail.
    public var isStreaming: Bool

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        createdAt: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}

public enum MessageRole: String, Sendable, Hashable, Codable, CaseIterable {
    case user
    case assistant
    case system
}
