import Foundation
import Models

/// One AI-authored line in the weekly digest. The `headline` is shown
/// large, the `body` reads as one sentence below it. `citations` carry
/// the `Transaction.id`s that justify the claim so the UI can jump to
/// the source rows when the user taps the bullet.
///
/// `kind` drives the leading accent dot color on the card and lets a
/// host re-order or theme bullets without parsing the prose.
public struct DigestBullet: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let kind: Kind
    public let headline: String
    public let body: String
    public let citations: [String]

    public init(
        id: String,
        kind: Kind,
        headline: String,
        body: String,
        citations: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.body = body
        self.citations = citations
    }

    public enum Kind: String, Sendable, Hashable, Codable {
        case spend
        case income
        case net
        case topCategory
        case subscriptions
        case anomaly
        case suggestion
    }
}

/// One complete weekly digest. The week is anchored to `weekStart`
/// (inclusive) through `weekEnd` (exclusive) so callers can render a
/// "May 11 — May 17" label without re-computing windows. The
/// `generatedAt` lets a host cache today's digest and regenerate when a
/// new week ticks over.
public struct Digest: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let weekStart: Date
    public let weekEnd: Date
    public let generatedAt: Date
    public let greeting: String
    public let bullets: [DigestBullet]

    public init(
        id: String,
        weekStart: Date,
        weekEnd: Date,
        generatedAt: Date,
        greeting: String,
        bullets: [DigestBullet]
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.generatedAt = generatedAt
        self.greeting = greeting
        self.bullets = bullets
    }
}
