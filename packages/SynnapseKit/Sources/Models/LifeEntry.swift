import Foundation

/// One row of the LIFE Terminal feed.
///
/// The Synapse v2 server does not expose a uniform `/api/life/entries` route
/// today — `/api/life/overview` returns an aggregated dashboard payload and
/// `/api/life/digest` returns LLM prose. Native-side, the terminal renders a
/// flat, monospaced timeline regardless of source. `LifeEntry` is the
/// canonical row the terminal reducer consumes; the networking layer is
/// responsible for synthesising entries out of whatever the server exposes
/// (today: a fan-out over `overview` + `outstanding` + a static "boot" line;
/// tomorrow: a real `/api/life/entries` stream, decoded into the same shape).
public struct LifeEntry: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let timestamp: Date
    public let kind: LifeEntryKind
    public let text: String
    public let metadata: [String: String]?

    public init(
        id: String,
        timestamp: Date,
        kind: LifeEntryKind,
        text: String,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.text = text
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, kind, text, metadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        // Server may emit either an ISO-8601 string or epoch milliseconds.
        // The terminal does not care about sub-second granularity but
        // does care about ordering, so both paths round-trip identically.
        if let iso = try? c.decode(String.self, forKey: .timestamp),
           let date = LifeEntry.parseTimestamp(iso) {
            self.timestamp = date
        } else if let ms = try? c.decode(Int64.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        } else if let s = try? c.decode(Double.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: s)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp, in: c,
                debugDescription: "timestamp must be ISO-8601 string or epoch number"
            )
        }
        let rawKind = try c.decode(String.self, forKey: .kind)
        self.kind = LifeEntryKind(rawValue: rawKind)
        self.text = try c.decode(String.self, forKey: .text)
        self.metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata)
    }
}

/// Kind of LIFE entry. Forward-compat: any server string we don't recognise
/// decodes as `.unknown` rather than failing — the terminal still renders the
/// line, just with the generic glyph.
public enum LifeEntryKind: String, Sendable, Equatable, CaseIterable {
    case boot
    case transaction
    case bill
    case insight
    case digest
    case streak
    case warning
    case unknown

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "boot": self = .boot
        case "transaction", "txn": self = .transaction
        case "bill", "recurring", "due": self = .bill
        case "insight": self = .insight
        case "digest": self = .digest
        case "streak": self = .streak
        case "warning", "warn", "alert": self = .warning
        default: self = .unknown
        }
    }

    /// One-glyph prefix used by the terminal reducer. Stays inside the
    /// strict 3-color palette — glyph itself paints in `phosphorBright`.
    public var glyph: String {
        switch self {
        case .boot: return "*"
        case .transaction: return "$"
        case .bill: return "!"
        case .insight: return ">"
        case .digest: return "#"
        case .streak: return "+"
        case .warning: return "?"
        case .unknown: return "-"
        }
    }
}

extension LifeEntry {
    /// Per-call formatters avoid a static `ISO8601DateFormatter` that
    /// Swift 6 strict concurrency rejects (the class is not Sendable).
    /// The cost is small compared to JSON decode itself.
    fileprivate static func parseTimestamp(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: s)
    }
}
