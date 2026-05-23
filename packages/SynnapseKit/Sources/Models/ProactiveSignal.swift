import Foundation

/// One item in the proactive feed the Dashboard inbox surfaces. The
/// `ProactiveAnalyzer` emits these from a periodic pass over the store; the
/// `id` is stable across runs so a nightly re-evaluation dedups against rows
/// already persisted rather than re-notifying the user about the same thing.
///
/// This is the in-memory shape. Phase 4's follow-on persists it as a
/// `@Model` so signals survive backgrounding and cross-device sync; the
/// fields here are the source of truth for that mirror.
public struct ProactiveSignal: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let kind: Kind
    public let headline: String
    public let body: String
    /// Transaction / account / predicted-charge id this signal points at, so
    /// the inbox row can jump to the underlying subject. `nil` when the
    /// signal is an aggregate with no single subject.
    public let subjectId: String?
    /// The instant the signal is "about" — a predicted charge date for bills,
    /// the evaluation time for anomalies. Drives recency sorting.
    public let date: Date
    public let severity: Severity

    public init(
        id: String,
        kind: Kind,
        headline: String,
        body: String,
        subjectId: String? = nil,
        date: Date,
        severity: Severity = .info
    ) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.body = body
        self.subjectId = subjectId
        self.date = date
        self.severity = severity
    }

    public enum Kind: String, Sendable, Hashable, Codable {
        /// A known recurring charge predicted to land within the lookahead.
        case upcomingBill
        /// A recurring cadence detected for a merchant not previously seen.
        case newRecurring
        /// Current-week spend in a category that clears the z-score threshold
        /// against its own trailing-weeks baseline.
        case anomalousSpend
    }

    public enum Severity: String, Sendable, Hashable, Codable {
        case info
        case warning
        case alert

        public var rank: Int {
            switch self {
            case .alert: return 3
            case .warning: return 2
            case .info: return 1
            }
        }
    }
}
