import Foundation

/// One person in the People surface — projection of an `/api/senders` row from
/// the Synapse v2 server (`lib/people.ts#listPeople` / `SenderStats`). Equality
/// + hashing are identity-only so the same person with shifted stats still
/// resolves to the same row.
///
/// The companion type [[PersonDossier]] extends `Person` with the heavier
/// per-identity payload returned by `/api/senders/[identity]`.
public struct Person: Sendable, Identifiable, Hashable {

    public var id: String { identity }
    public let identity: String
    public let displayName: String
    public let importanceWeight: Double
    public let autoBoost: Double
    public let effectiveWeight: Double
    public let blacklisted: Bool
    public let notes: String?
    public let totalMessages: Int
    public let firstSeen: Date?
    public let lastSeen: Date?
    public let distinctThreads: Int
    public let awaitingMyReply: Int
    public let openActions: Int
    public let sources: [Source]
    public let avgImportance: Double
    public let avatarURL: URL?
    public let avatarStatus: AvatarStatus?
    /// Either the operator's manual `kindOverride`, or the heuristic verdict
    /// when the override is absent. Resolved once on projection so views
    /// don't re-classify on every render.
    public let kind: PersonKind

    public init(
        identity: String,
        displayName: String,
        importanceWeight: Double,
        autoBoost: Double,
        effectiveWeight: Double,
        blacklisted: Bool,
        notes: String?,
        totalMessages: Int,
        firstSeen: Date?,
        lastSeen: Date?,
        distinctThreads: Int,
        awaitingMyReply: Int,
        openActions: Int,
        sources: [Source],
        avgImportance: Double,
        avatarURL: URL?,
        avatarStatus: AvatarStatus?,
        kind: PersonKind
    ) {
        self.identity = identity
        self.displayName = displayName
        self.importanceWeight = importanceWeight
        self.autoBoost = autoBoost
        self.effectiveWeight = effectiveWeight
        self.blacklisted = blacklisted
        self.notes = notes
        self.totalMessages = totalMessages
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.distinctThreads = distinctThreads
        self.awaitingMyReply = awaitingMyReply
        self.openActions = openActions
        self.sources = sources
        self.avgImportance = avgImportance
        self.avatarURL = avatarURL
        self.avatarStatus = avatarStatus
        self.kind = kind
    }

    // Identity-only equality + hashing — same email = same person, regardless
    // of how the stats may have shifted between fetches.
    public static func == (lhs: Person, rhs: Person) -> Bool {
        lhs.identity == rhs.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }
}

extension Person: Decodable {
    private enum CodingKeys: String, CodingKey {
        case identity, displayName
        case importanceWeight, autoBoost, effectiveWeight
        case blacklisted, notes
        case totalMessages, firstSeen, lastSeen, distinctThreads
        case awaitingMyReply, openActions, sources, avgImportance
        case avatarUrl, avatarURL, avatarStatus
        case kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identity = try c.decode(String.self, forKey: .identity)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.importanceWeight = try c.decode(Double.self, forKey: .importanceWeight)
        self.autoBoost = try c.decode(Double.self, forKey: .autoBoost)
        self.effectiveWeight = try c.decode(Double.self, forKey: .effectiveWeight)
        self.blacklisted = try c.decode(Bool.self, forKey: .blacklisted)
        self.notes = try? c.decode(String?.self, forKey: .notes) ?? nil
        self.totalMessages = try c.decode(Int.self, forKey: .totalMessages)
        self.firstSeen = try c.decodeIfPresent(Date.self, forKey: .firstSeen)
        self.lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        self.distinctThreads = try c.decode(Int.self, forKey: .distinctThreads)
        self.awaitingMyReply = try c.decode(Int.self, forKey: .awaitingMyReply)
        self.openActions = try c.decode(Int.self, forKey: .openActions)
        let rawSources = try c.decode([String].self, forKey: .sources)
        self.sources = rawSources.map { Source(rawValue: $0) ?? .unknown }
        self.avgImportance = try c.decode(Double.self, forKey: .avgImportance)
        // Tolerate both camelCase shapes the route can emit.
        let urlString = try c.decodeIfPresent(String.self, forKey: .avatarURL)
            ?? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        self.avatarURL = urlString.flatMap(URL.init(string:))
        self.avatarStatus = try c.decodeIfPresent(AvatarStatus.self, forKey: .avatarStatus)
        self.kind = try c.decodeIfPresent(PersonKind.self, forKey: .kind) ?? .person
    }
}

/// Person vs. mailing-list / no-reply entity classification. The server today
/// exposes a `kindOverride` field (operator-pinned); when absent we run the
/// same heuristic the web app uses (`lib/people/classify.ts`) inline.
public enum PersonKind: String, Codable, Sendable, Hashable, CaseIterable {
    case person
    case entity
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PersonKind(rawValue: raw) ?? .unknown
    }
}

/// One message in the inbox / per-source channel. Mirrors `Message.source`
/// from the Synapse v2 Drizzle schema. `.unknown` is the forward-compat
/// landing pad so a new server-side value never breaks the decoder.
public enum Source: String, Codable, Sendable, Hashable, CaseIterable {
    case gmail
    case calendar
    case slack
    case outlook
    case discord
    case pipeline
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Source(rawValue: raw) ?? .unknown
    }
}

/// Avatar pipeline state. Mirrors `avatarStatusEnum` in the Drizzle schema.
public enum AvatarStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case pending, found, rejected, manual

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AvatarStatus(rawValue: raw) ?? .pending
    }
}

// MARK: - Server wire shape

/// Wire-level row from `GET /api/senders` (route → `SenderStats`).
public struct ServerSenderRow: Decodable, Sendable {
    public let identity: String
    public let displayName: String
    public let importanceWeight: Double
    public let autoBoost: Double
    public let effectiveWeight: Double
    public let blacklisted: Bool
    public let notes: String?
    public let totalMessages: Int
    public let firstSeen: String?
    public let lastSeen: String?
    public let distinctThreads: Int
    public let awaitingMyReply: Int
    public let openActions: Int
    public let sources: [String]
    public let avgImportance: Double
    public let avatarUrl: String?
    public let avatarSource: String?
    public let avatarStatus: String?
    public let avatarScore: Double?
    public let kindOverride: String?

    public init(
        identity: String, displayName: String,
        importanceWeight: Double, autoBoost: Double, effectiveWeight: Double,
        blacklisted: Bool, notes: String?,
        totalMessages: Int, firstSeen: String?, lastSeen: String?,
        distinctThreads: Int, awaitingMyReply: Int, openActions: Int,
        sources: [String], avgImportance: Double,
        avatarUrl: String?, avatarSource: String?, avatarStatus: String?,
        avatarScore: Double?, kindOverride: String?
    ) {
        self.identity = identity
        self.displayName = displayName
        self.importanceWeight = importanceWeight
        self.autoBoost = autoBoost
        self.effectiveWeight = effectiveWeight
        self.blacklisted = blacklisted
        self.notes = notes
        self.totalMessages = totalMessages
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.distinctThreads = distinctThreads
        self.awaitingMyReply = awaitingMyReply
        self.openActions = openActions
        self.sources = sources
        self.avgImportance = avgImportance
        self.avatarUrl = avatarUrl
        self.avatarSource = avatarSource
        self.avatarStatus = avatarStatus
        self.avatarScore = avatarScore
        self.kindOverride = kindOverride
    }
}

public struct ServerSendersListResponse: Decodable, Sendable {
    public let senders: [ServerSenderRow]
}

extension Person {
    /// Project a server row into the native `Person`. Resolves `kindOverride`
    /// against the bundled heuristic when the operator hasn't manually pinned
    /// the classification.
    public static func fromServerRow(_ row: ServerSenderRow) -> Person {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        func date(_ s: String?) -> Date? {
            guard let s else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        let kind: PersonKind
        if let override = row.kindOverride, let v = PersonKind(rawValue: override) {
            kind = v
        } else {
            kind = PeopleHeuristic.classify(
                identity: row.identity,
                displayName: row.displayName
            )
        }
        return Person(
            identity: row.identity,
            displayName: row.displayName,
            importanceWeight: row.importanceWeight,
            autoBoost: row.autoBoost,
            effectiveWeight: row.effectiveWeight,
            blacklisted: row.blacklisted,
            notes: row.notes,
            totalMessages: row.totalMessages,
            firstSeen: date(row.firstSeen),
            lastSeen: date(row.lastSeen),
            distinctThreads: row.distinctThreads,
            awaitingMyReply: row.awaitingMyReply,
            openActions: row.openActions,
            sources: row.sources.map { Source(rawValue: $0) ?? .unknown },
            avgImportance: row.avgImportance,
            avatarURL: row.avatarUrl.flatMap(URL.init(string:)),
            avatarStatus: row.avatarStatus.flatMap(AvatarStatus.init(rawValue:)),
            kind: kind
        )
    }
}

/// Bundled person-vs-entity heuristic. Mirrors the rules from
/// `lib/people/classify.ts` in the Synapse v2 codebase — no-reply, mailer-
/// daemon, plus mailing-list-shape senders fall into `.entity`; everything
/// else with a real human-shape display name is `.person`.
public enum PeopleHeuristic {
    public static func classify(identity: String, displayName: String) -> PersonKind {
        let id = identity.lowercased()
        let name = displayName.lowercased()
        let entitySignals = [
            "no-reply", "noreply", "no_reply",
            "mailer-daemon", "postmaster",
            "notifications@", "alerts@", "support@", "team@",
            "bounce@", "info@", "billing@"
        ]
        for sig in entitySignals where id.contains(sig) || name.contains(sig) {
            return .entity
        }
        // A bare brand-name display ("Stripe", "GitHub") combined with a
        // generic "no-reply"-shape inbox is the most common entity pattern.
        // Treat single-token brand names as entities only if the address
        // local-part itself looks generic.
        if !displayName.contains(" "),
           id.hasPrefix("no-") || id.hasPrefix("info") || id.contains("noreply") {
            return .entity
        }
        return .person
    }
}

// MARK: - Dossier

public struct DossierMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let source: Source
    public let subject: String?
    public let receivedAt: Date
    public let category: String?
    public let awaitingMyReply: Bool
    public let rank: Double

    public init(
        id: String, source: Source, subject: String?,
        receivedAt: Date, category: String?,
        awaitingMyReply: Bool, rank: Double
    ) {
        self.id = id
        self.source = source
        self.subject = subject
        self.receivedAt = receivedAt
        self.category = category
        self.awaitingMyReply = awaitingMyReply
        self.rank = rank
    }
}

public struct DossierActionItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let text: String
    public let dueAt: Date?
    public let messageId: String
    public let messageSubject: String?

    public init(
        id: String, text: String, dueAt: Date?,
        messageId: String, messageSubject: String?
    ) {
        self.id = id
        self.text = text
        self.dueAt = dueAt
        self.messageId = messageId
        self.messageSubject = messageSubject
    }
}

/// Heavy per-identity payload returned by `GET /api/senders/[identity]`.
/// Stitches the person headline with the recent message tail and any
/// outstanding action items.
public struct PersonDossier: Sendable, Equatable {
    public let person: Person
    public let recentMessages: [DossierMessage]
    public let openActionItems: [DossierActionItem]

    public init(
        person: Person,
        recentMessages: [DossierMessage],
        openActionItems: [DossierActionItem]
    ) {
        self.person = person
        self.recentMessages = recentMessages
        self.openActionItems = openActionItems
    }
}
