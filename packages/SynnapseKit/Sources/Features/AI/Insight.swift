import Foundation
import Models

/// A typed AI insight surfaced inline next to data. Three kinds today:
/// `.anomaly` for outlier flags, `.forecast` for projected end-state,
/// `.pattern` for week-over-week shape changes. Each carries a primary
/// `headline` (one short sentence) and a `body` (one sentence of
/// reasoning). The optional `accountId` lets a card jump-to-account on
/// tap; the optional `severity` paints the leading edge of the card.
///
/// Wire shape mirrors the server-side `/api/ai/insights` route that
/// synapse-v2 has not yet shipped. The `LocalStubInsightsAPI` computes
/// the same envelope client-side from a `(accounts, transactions)`
/// snapshot so the UI is never empty when the server is offline.
public struct Insight: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let kind: Kind
    public let headline: String
    public let body: String
    public let accountId: String?
    public let severity: Severity

    public init(
        id: String,
        kind: Kind,
        headline: String,
        body: String,
        accountId: String? = nil,
        severity: Severity = .info
    ) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.body = body
        self.accountId = accountId
        self.severity = severity
    }

    public enum Kind: String, Sendable, Hashable, Codable {
        case anomaly
        case forecast
        case pattern
        case narration
    }

    /// Drives the leading-edge accent. `.info` and `.positive` keep the
    /// neutral / gain tone; `.warning` and `.alert` surface the loss tone
    /// so the user notices without the card becoming a popup.
    public enum Severity: String, Sendable, Hashable, Codable {
        case info
        case positive
        case warning
        case alert
    }
}
