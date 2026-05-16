import Foundation

/// One spotlight event surfaced by `/api/spotlight` (and adjacent routes) on
/// the Synapse v2 server. Field shape mirrors the route handler verbatim — see
/// `app/api/spotlight/route.ts`. `nextCursor` is a forward-compatible extension
/// the client honors when the server starts paginating; today the server
/// returns the full list and the cursor is absent.
public struct SpotlightPage: Decodable, Sendable, Equatable {
    public let events: [SpotlightItem]
    public let nextCursor: String?

    public init(events: [SpotlightItem], nextCursor: String? = nil) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

public struct SpotlightMessage: Decodable, Sendable, Equatable {
    public let senderDisplay: String
    public let sender: String
    public let subject: String
    public let receivedAt: Date
    public let body: String?
    public let threadId: String?

    public init(
        senderDisplay: String,
        sender: String,
        subject: String,
        receivedAt: Date,
        body: String?,
        threadId: String?
    ) {
        self.senderDisplay = senderDisplay
        self.sender = sender
        self.subject = subject
        self.receivedAt = receivedAt
        self.body = body
        self.threadId = threadId
    }
}

public struct SpotlightItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let messageId: String
    public let kind: String
    public let issueLabel: String?
    public let summary: String?
    /// JSON blob the server persists alongside each pick. Carries the top
    /// candidate metadata (title, authors, PDF URL, venue tag) — see
    /// `lib/spotlight/pipeline.ts`'s `RunLinkPayload`. Surface as raw String
    /// here; callers parse on demand via `topCandidate()`.
    public let runLink: String?
    public let paperUrl: URL?
    public let overleafUrl: URL?
    public var status: String
    public let detectedAt: Date
    public let decidedAt: Date?
    public let message: SpotlightMessage

    public init(
        id: String,
        messageId: String,
        kind: String,
        issueLabel: String?,
        summary: String?,
        runLink: String?,
        paperUrl: URL?,
        overleafUrl: URL?,
        status: String,
        detectedAt: Date,
        decidedAt: Date?,
        message: SpotlightMessage
    ) {
        self.id = id
        self.messageId = messageId
        self.kind = kind
        self.issueLabel = issueLabel
        self.summary = summary
        self.runLink = runLink
        self.paperUrl = paperUrl
        self.overleafUrl = overleafUrl
        self.status = status
        self.detectedAt = detectedAt
        self.decidedAt = decidedAt
        self.message = message
    }
}

extension SpotlightItem: Equatable, Hashable {
    // Identity is by id alone — the same id with mutated status (e.g. operator
    // moved `pending → actioned`) is still the same logical item.
    public static func == (lhs: SpotlightItem, rhs: SpotlightItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct SpotlightCandidate: Decodable, Sendable, Equatable {
    public let title: String
    public let authors: [String]
    public let relevanceScore: Double?
    public let abstractUrl: URL?
    public let pdfUrl: URL?
    public let venueTag: String?
    public let arxivId: String?

    public init(
        title: String,
        authors: [String],
        relevanceScore: Double?,
        abstractUrl: URL?,
        pdfUrl: URL?,
        venueTag: String?,
        arxivId: String?
    ) {
        self.title = title
        self.authors = authors
        self.relevanceScore = relevanceScore
        self.abstractUrl = abstractUrl
        self.pdfUrl = pdfUrl
        self.venueTag = venueTag
        self.arxivId = arxivId
    }
}

private struct RunLinkEnvelope: Decodable, Sendable {
    let kind: String?
    let candidates: [SpotlightCandidate]?
}

extension SpotlightItem {
    /// Decodes the embedded `runLink` JSON and returns the top candidate, or
    /// nil when the field is absent / malformed.
    public func topCandidate() -> SpotlightCandidate? {
        guard let runLink, let data = runLink.data(using: .utf8) else { return nil }
        let env = try? JSONDecoder().decode(RunLinkEnvelope.self, from: data)
        return env?.candidates?.first
    }
}

// MARK: - Decoding

extension JSONDecoder {
    /// Shared decoder for Synnapse server payloads. The server emits ISO-8601
    /// with fractional seconds (`2026-05-10T14:30:00.000Z`); the system
    /// default `.iso8601` strategy without fractional seconds chokes on the
    /// `.000` suffix.
    public static let synnapseSpotlight: JSONDecoder = {
        let dec = JSONDecoder()
        // ISO8601DateFormatter is not Sendable; construct fresh instances per
        // call. Decoding is invoked synchronously per JSON document so the
        // overhead is negligible and the closure stays @Sendable-clean.
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
