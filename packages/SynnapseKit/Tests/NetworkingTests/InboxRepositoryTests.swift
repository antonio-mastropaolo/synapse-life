import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

/// Network-level tests for the Inbox surface. Mirrors `/api/messages` with
/// added query params for pagination + source filter. ETag/304 is forward-
/// compat — the server today returns no ETag, but the client must tolerate
/// one when added.
@Suite("InboxRepository")
struct InboxRepositoryTests {

    private func messagesBody(
        rows: Int,
        startId: Int = 0,
        totalOverride: Int? = nil,
        nextCursor: String? = nil
    ) -> Data {
        let messages: [[String: Any]] = (0..<rows).map { i in
            [
                "id": "m-\(startId + i)",
                "source": "gmail",
                "externalId": "ext-\(startId + i)",
                "threadId": NSNull(),
                "sender": "p\(startId + i)@x.io",
                "senderDisplay": "P \(startId + i)",
                "recipients": ["me@x.io"],
                "subject": "Subj \(startId + i)",
                "body": "Body \(startId + i)",
                "receivedAt": "2026-05-15T14:30:00.000Z",
                "createdAt": "2026-05-15T14:30:00.000Z",
                "insight": NSNull(),
                "actionItems": []
            ]
        }
        let total = totalOverride ?? rows
        var payload: [String: Any] = [
            "total": total, "messages": messages
        ]
        if let nextCursor {
            payload["nextCursor"] = nextCursor
        }
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private func makeClient(session: URLSession) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://api.synnapse.test/v1/")!,
            session: session,
            defaultHeaders: ["Accept": "application/json"],
            auth: nil,
            retry: .none
        )
    }

    @Test
    func listFetchDecodesMessages() async throws {
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.hasSuffix("/api/messages") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json", "ETag": "\"m-v1\""],
                body: self.messagesBody(rows: 4, totalOverride: 4)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveInboxAPI(client: makeClient(session: session))
        let repo = InboxRepository(api: api)
        try await repo.refresh()
        let items = await repo.items
        #expect(items.count == 4)
        #expect(items.first?.id == "m-0")
    }

    @Test
    func loadMoreAppendsPaginationByCursor() async throws {
        let counter = InboxAtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            let q = request.url?.query ?? ""
            if n == 1 {
                #expect(!q.contains("cursor="))
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: self.messagesBody(
                        rows: 2, startId: 0, totalOverride: 5,
                        nextCursor: "page-2"
                    )
                ))
            }
            #expect(q.contains("cursor=page-2"))
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.messagesBody(rows: 2, startId: 2, totalOverride: 5)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveInboxAPI(client: makeClient(session: session), pageSize: 2)
        let repo = InboxRepository(api: api)
        try await repo.refresh()
        #expect(await repo.items.count == 2)
        try await repo.loadMore()
        let items = await repo.items
        #expect(items.count == 4)
        #expect(items.map(\.id) == ["m-0", "m-1", "m-2", "m-3"])
    }

    @Test
    func cacheSurvives304() async throws {
        let counter = InboxAtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            if n == 1 {
                return .success(.init(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/json",
                        "ETag": "\"i-1\""
                    ],
                    body: self.messagesBody(rows: 1)
                ))
            }
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"i-1\"")
            return .success(.init(statusCode: 304, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveInboxAPI(client: makeClient(session: session))
        let repo = InboxRepository(api: api)
        try await repo.refresh()
        #expect(await repo.items.count == 1)
        try await repo.refresh()
        #expect(await repo.items.count == 1) // cache survives
    }

    @Test
    func markReadEmitsPatchRequest() async throws {
        let counter = InboxAtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            if n == 1 {
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: self.messagesBody(rows: 1)
                ))
            }
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path.contains("/api/messages/m-0") == true)
            // Server contract for read flag is not live yet — return 200 OK
            // to keep the optimistic flow happy on hosts that mock it.
            return .success(.init(statusCode: 200, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveInboxAPI(client: makeClient(session: session))
        let repo = InboxRepository(api: api)
        try await repo.refresh()
        try await api.markRead(id: "m-0", read: true)
        #expect(counter.value == 2)
    }
}

final class InboxAtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var n: Int = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}
