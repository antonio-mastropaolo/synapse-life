import Foundation
import Testing
@testable import Networking

struct Item: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

actor FakeAuth: AuthInterceptor {
    private var token: String
    private(set) var refreshCount: Int = 0

    init(initial: String) { self.token = initial }

    func currentAccessToken() async -> String? { token }

    func refresh() async throws -> String {
        refreshCount += 1
        token = "refreshed-\(refreshCount)"
        return token
    }
}

private func makeClient(
    session: URLSession,
    auth: AuthInterceptor? = nil,
    retry: RetryPolicy = .none
) throws -> APIClient {
    let baseURL = try #require(URL(string: "https://api.synapse.test/v1/"))
    return APIClient(
        baseURL: baseURL,
        session: session,
        defaultHeaders: ["Accept": "application/json"],
        auth: auth,
        retry: retry
    )
}

@Suite("APIClient")
struct APIClientTests {

    @Test
    func decodesHappyPathGet() async throws {
        let body = try JSONEncoder().encode(Item(id: 7, name: "alpha"))
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let client = try makeClient(session: session)
        let item = try await client.send(Endpoint<Item>(path: "items/7"))
        #expect(item == Item(id: 7, name: "alpha"))
    }

    @Test
    func refreshesOnceOn401ThenSucceeds() async throws {
        let body = try JSONEncoder().encode(Item(id: 1, name: "ok"))
        let counter = ResponseCounter()
        let session = URLProtocolStub.makeSession { _ in
            let n = counter.next()
            if n == 1 {
                return .success(.init(statusCode: 401, body: Data()))
            }
            return .success(.init(statusCode: 200, body: body))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let auth = FakeAuth(initial: "stale")
        let client = try makeClient(session: session, auth: auth)
        let item = try await client.send(Endpoint<Item>(path: "items/1"))
        #expect(item.id == 1)
        let refreshes = await auth.refreshCount
        #expect(refreshes == 1)
    }

    @Test
    func secondConsecutive401SurfacesUnauthorized() async throws {
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(statusCode: 401, body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let auth = FakeAuth(initial: "stale")
        let client = try makeClient(session: session, auth: auth)
        await #expect(throws: APIError.unauthorized) {
            _ = try await client.send(Endpoint<Item>(path: "items/1"))
        }
        let refreshes = await auth.refreshCount
        #expect(refreshes == 1)
    }

    @Test
    func retriesOn500WithBackoffUpToN() async throws {
        let counter = ResponseCounter()
        let session = URLProtocolStub.makeSession { _ in
            _ = counter.next()
            return .success(.init(statusCode: 500, body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let client = try makeClient(
            session: session,
            retry: RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1))
        )
        await #expect(throws: APIError.server(status: 500)) {
            _ = try await client.send(Endpoint<Item>(path: "items/1"))
        }
        #expect(counter.value == 3)
    }

    @Test
    func cancellationPropagates() async throws {
        let session = URLProtocolStub.makeSession { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return .success(.init(statusCode: 200, body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let client = try makeClient(session: session)
        let task = Task {
            try await client.send(Endpoint<Item>(path: "items/1"))
        }
        task.cancel()

        await #expect(throws: (any Error).self) {
            _ = try await task.value
        }
    }
}

// Thread-safe counter so the URLProtocol handler can keep call ordering.
final class ResponseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return n
    }

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        n += 1
        return n
    }
}
