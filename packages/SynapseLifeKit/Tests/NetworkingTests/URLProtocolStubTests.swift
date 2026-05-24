import Foundation
import Testing
@testable import Networking

@Suite("URLProtocolStub harness")
struct URLProtocolStubTests {

    @Test
    func returnsCannedResponseForMatchedRequest() async throws {
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(statusCode: 200, body: Data("hello".utf8)))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let url = try #require(URL(string: "https://example.test/ping"))
        let (data, response) = try await session.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "hello")
    }

    @Test
    func recordsRequestsItSaw() async throws {
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(statusCode: 204, body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let urlA = try #require(URL(string: "https://example.test/a"))
        let urlB = try #require(URL(string: "https://example.test/b"))
        _ = try await session.data(from: urlA)
        _ = try await session.data(from: urlB)

        let recorded = URLProtocolStub.requests(for: session)
        #expect(recorded.count == 2)
        #expect(recorded.first?.url?.path == "/a")
        #expect(recorded.last?.url?.path == "/b")
    }

    @Test
    func surfacesErrorWhenHandlerFails() async throws {
        struct Boom: Error {}
        let session = URLProtocolStub.makeSession { _ in .failure(Boom()) }
        defer { URLProtocolStub.releaseSession(session) }

        let url = try #require(URL(string: "https://example.test/x"))
        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: url)
        }
    }
}
