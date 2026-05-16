import Foundation
import Models

/// Result of a People list fetch. ETag + 304 are forward-compat (the v2
/// `/api/senders` route doesn't emit ETag today, but will).
public struct PeopleResponse: Sendable, Equatable {
    public let people: [Person]?
    public let etag: String?
    public let notModified: Bool

    public init(people: [Person]?, etag: String?, notModified: Bool) {
        self.people = people
        self.etag = etag
        self.notModified = notModified
    }
}

public protocol PeopleAPI: Sendable {
    func list(ifNoneMatch: String?) async throws -> PeopleResponse
    func dossier(for identity: String) async throws -> PersonDossier
}

/// Wire-level envelope for `/api/senders/[identity]` — the dossier shape from
/// `lib/people.ts#getDossier`. We tolerate a missing `recentMessages` /
/// `openActionItems` block (server adds those lazily).
private struct DossierEnvelope: Decodable {
    let identity: String
    let displayName: String
    let importanceWeight: Double
    let autoBoost: Double
    let effectiveWeight: Double
    let blacklisted: Bool
    let notes: String?
    let totalMessages: Int
    let firstSeen: String?
    let lastSeen: String?
    let distinctThreads: Int
    let awaitingMyReply: Int
    let openActions: Int
    let sources: [String]
    let avgImportance: Double
    let avatarUrl: String?
    let avatarSource: String?
    let avatarStatus: String?
    let avatarScore: Double?
    let kindOverride: String?
    let recentMessages: [DossierMessageRow]?
    let openActionItems: [DossierActionItemRow]?
}

private struct DossierMessageRow: Decodable {
    let id: String
    let source: String
    let subject: String?
    let body: String?
    let receivedAt: String
    let category: String?
    let awaitingMyReply: Bool
    let rank: Double
}

private struct DossierActionItemRow: Decodable {
    let id: String
    let text: String
    let dueAt: String?
    let messageId: String
    let messageSubject: String?
}

/// Live implementation. Drops to URLSession directly so the 304 / ETag path
/// works (the typed `APIClient.send` treats 304 as an error).
public struct LivePeopleAPI: PeopleAPI {
    private let baseURL: URL
    private let session: URLSession

    public init(client: APIClient) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
    }

    public func list(ifNoneMatch: String?) async throws -> PeopleResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/senders"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag")
        if http.statusCode == 304 {
            return PeopleResponse(people: nil, etag: etag, notModified: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(ServerSendersListResponse.self, from: data)
            let people = envelope.senders.map(Person.fromServerRow)
            return PeopleResponse(people: people, etag: etag, notModified: false)
        } catch {
            throw APIError.decoding
        }
    }

    public func dossier(for identity: String) async throws -> PersonDossier {
        let path = "api/senders/\(percentEncoded(identity))"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let env = try JSONDecoder().decode(DossierEnvelope.self, from: data)
            return projection(of: env)
        } catch {
            throw APIError.decoding
        }
    }

    private func percentEncoded(_ s: String) -> String {
        // The identity is an email address; `@` is technically safe in a
        // path segment but several proxies still mangle it. Encode for
        // safety while leaving the common chars readable.
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "@"))
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func projection(of env: DossierEnvelope) -> PersonDossier {
        let row = ServerSenderRow(
            identity: env.identity, displayName: env.displayName,
            importanceWeight: env.importanceWeight, autoBoost: env.autoBoost,
            effectiveWeight: env.effectiveWeight,
            blacklisted: env.blacklisted, notes: env.notes,
            totalMessages: env.totalMessages,
            firstSeen: env.firstSeen, lastSeen: env.lastSeen,
            distinctThreads: env.distinctThreads,
            awaitingMyReply: env.awaitingMyReply,
            openActions: env.openActions,
            sources: env.sources, avgImportance: env.avgImportance,
            avatarUrl: env.avatarUrl, avatarSource: env.avatarSource,
            avatarStatus: env.avatarStatus, avatarScore: env.avatarScore,
            kindOverride: env.kindOverride
        )
        let person = Person.fromServerRow(row)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        func date(_ s: String?) -> Date {
            guard let s else { return Date(timeIntervalSince1970: 0) }
            return iso.date(from: s) ?? isoPlain.date(from: s) ?? Date(timeIntervalSince1970: 0)
        }
        let messages: [DossierMessage] = (env.recentMessages ?? []).map { r in
            DossierMessage(
                id: r.id,
                source: Source(rawValue: r.source) ?? .unknown,
                subject: r.subject,
                receivedAt: date(r.receivedAt),
                category: r.category,
                awaitingMyReply: r.awaitingMyReply,
                rank: r.rank
            )
        }
        let actions: [DossierActionItem] = (env.openActionItems ?? []).map { r in
            DossierActionItem(
                id: r.id, text: r.text,
                dueAt: r.dueAt.map { date($0) },
                messageId: r.messageId,
                messageSubject: r.messageSubject
            )
        }
        return PersonDossier(person: person, recentMessages: messages, openActionItems: actions)
    }
}

// `MockPeopleAPI` lives in the `Features` target so the SnapshotTests target
// (which depends only on Features / Models / DesignSystem) can construct
// view models with a mock seam. See `Features/People/PeopleMockAPI.swift`.
