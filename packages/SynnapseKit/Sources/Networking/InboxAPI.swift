import Foundation
import Models

public struct InboxResponse: Sendable, Equatable {
    public let page: InboxPage?
    public let etag: String?
    public let notModified: Bool

    public init(page: InboxPage?, etag: String?, notModified: Bool) {
        self.page = page
        self.etag = etag
        self.notModified = notModified
    }
}

/// Inbox network seam. The route is `/api/messages` on the Synapse v2
/// server today; it returns all messages in one shot (no real pagination yet).
/// We support a `cursor` and `limit` param on the client side so the future
/// paginated route can land without a client rev. Mark-read is a forward-
/// compat `PATCH /api/messages/:id` endpoint; the server has no `read`
/// column yet, so the local-only flow remains source of truth.
public protocol InboxAPI: Sendable {
    func list(
        cursor: String?,
        source: Source?,
        ifNoneMatch: String?
    ) async throws -> InboxResponse

    /// Optimistically inform the server that the given message has been
    /// read. Server contract NOT live in v2 — calls today route to the
    /// `messages/:id/analyze` POST or simply 404; the caller is expected to
    /// handle either as a soft failure (the optimistic UI keeps state).
    func markRead(id: String, read: Bool) async throws
}

public struct LiveInboxAPI: InboxAPI {
    private let baseURL: URL
    private let session: URLSession
    private let pageSize: Int

    public init(client: APIClient, pageSize: Int = 50) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
        self.pageSize = pageSize
    }

    public func list(
        cursor: String?,
        source: Source?,
        ifNoneMatch: String?
    ) async throws -> InboxResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/messages"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(pageSize))
        ]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let source {
            queryItems.append(URLQueryItem(name: "source", value: source.rawValue))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag")
        if http.statusCode == 304 {
            return InboxResponse(page: nil, etag: etag, notModified: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let page = try JSONDecoder.synnapseInbox.decode(InboxPage.self, from: data)
            return InboxResponse(page: page, etag: etag, notModified: false)
        } catch {
            throw APIError.decoding
        }
    }

    public func markRead(id: String, read: Bool) async throws {
        let url = baseURL.appendingPathComponent("api/messages/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["read": read]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        // 200/204 = ok; 404 = endpoint not yet live (treat as success because
        // the server simply doesn't carry the flag yet — the client-side
        // projection is the source of truth until then).
        if http.statusCode == 404 { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
    }
}

// `MockInboxAPI` lives in the `Features` target — see
// `Features/Inbox/InboxMockAPI.swift`. Same rationale as `MockPeopleAPI`:
// the SnapshotTests target only depends on Features / Models / DesignSystem.
