import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func okBody(events: Int, idPrefix: String = "evt", nextCursor: String? = nil) -> Data {
    var dict: [String: Any] = [:]
    let evts: [[String: Any]] = (0..<events).map { i in
        [
            "id": "\(idPrefix)-\(i)",
            "messageId": "msg-\(i)",
            "kind": "pick",
            "issueLabel": "ISSUE-2026-05-MAY",
            "summary": "summary \(i)",
            "runLink": NSNull(),
            "paperUrl": NSNull(),
            "overleafUrl": NSNull(),
            "status": "pending",
            "detectedAt": "2026-05-10T14:30:00.000Z",
            "decidedAt": NSNull(),
            "message": [
                "senderDisplay": "Test",
                "sender": "test@x.io",
                "subject": "S",
                "receivedAt": "2026-05-10T14:00:00.000Z",
                "body": NSNull(),
                "threadId": NSNull()
            ]
        ]
    }
    dict["events"] = evts
    if let nextCursor {
        dict["nextCursor"] = nextCursor
    }
    return try! JSONSerialization.data(withJSONObject: dict)
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

@Suite("SpotlightRepository")
struct SpotlightRepositoryTests {

    @Test
    func listDecodesAgainstStub() async throws {
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json", "ETag": "\"v1\""],
                body: okBody(events: 3)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSpotlightAPI(client: makeClient(session: session))
        let repo = SpotlightRepository(api: api)
        try await repo.refresh()
        let items = await repo.items
        #expect(items.count == 3)
        #expect(items.first?.id == "evt-0")
    }

    @Test
    func loadMoreFollowsCursor() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            if n == 1 {
                #expect(request.url?.query?.contains("cursor=") != true)
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: okBody(events: 2, idPrefix: "page1", nextCursor: "c2")
                ))
            }
            #expect(request.url?.query?.contains("cursor=c2") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: okBody(events: 2, idPrefix: "page2")
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSpotlightAPI(client: makeClient(session: session))
        let repo = SpotlightRepository(api: api)
        try await repo.refresh()
        try await repo.loadMore()
        let items = await repo.items
        #expect(items.map(\.id) == ["page1-0", "page1-1", "page2-0", "page2-1"])
    }

    @Test
    func loadMoreStopsWhenServerHasNoCursor() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { _ in
            _ = counter.next()
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: okBody(events: 1)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSpotlightAPI(client: makeClient(session: session))
        let repo = SpotlightRepository(api: api)
        try await repo.refresh()
        try await repo.loadMore()
        try await repo.loadMore()
        #expect(counter.value == 1)
    }

    @Test
    func scopePassedAsQueryParam() async throws {
        let lastURL = AtomicString()
        let session = URLProtocolStub.makeSession { request in
            lastURL.set(request.url?.absoluteString ?? "")
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: okBody(events: 0)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSpotlightAPI(client: makeClient(session: session))
        let repo = SpotlightRepository(api: api, scope: .picks)
        try await repo.refresh()
        #expect(lastURL.value.contains("scope=picks"))
    }

    @Test
    func etagReuseSurvives304() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            if n == 1 {
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json", "ETag": "\"abc\""],
                    body: okBody(events: 2)
                ))
            }
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
            return .success(.init(statusCode: 304, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSpotlightAPI(client: makeClient(session: session))
        let repo = SpotlightRepository(api: api)
        try await repo.refresh()
        let before = await repo.items.map(\.id)
        try await repo.refresh()
        let after = await repo.items.map(\.id)
        #expect(before == after)
        #expect(after.count == 2)
    }
}

// Thread-safe scratch helpers — duplicating the existing `ResponseCounter`
// shape with a friendlier API for these tests.
final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var n: Int = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

final class AtomicString: @unchecked Sendable {
    private let lock = NSLock()
    private var s: String = ""
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
    func set(_ v: String) { lock.lock(); defer { lock.unlock() }; s = v }
}
