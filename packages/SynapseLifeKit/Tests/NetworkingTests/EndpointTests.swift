import Foundation
import Testing
@testable import Networking

struct Echo: Decodable, Sendable, Equatable { let ok: Bool }

@Suite("Endpoint composition")
struct EndpointTests {

    private func makeBase() throws -> URL {
        try #require(URL(string: "https://api.synapse.test/v1/"))
    }

    @Test
    func composesPathAndQuery() throws {
        let endpoint = Endpoint<Echo>(
            method: .get,
            path: "items",
            query: [URLQueryItem(name: "page", value: "2")]
        )
        let url = try endpoint.url(relativeTo: makeBase())
        #expect(url.absoluteString == "https://api.synapse.test/v1/items?page=2")
    }

    @Test
    func handlesLeadingSlashInPath() throws {
        let endpoint = Endpoint<Echo>(path: "/items/42")
        let url = try endpoint.url(relativeTo: makeBase())
        #expect(url.absoluteString == "https://api.synapse.test/v1/items/42")
    }

    @Test
    func endpointHeadersOverrideDefaults() {
        let endpoint = Endpoint<Echo>(
            path: "x",
            headers: ["Accept": "application/vnd.synapse+json"]
        )
        let merged = endpoint.merged(defaults: [
            "Accept": "application/json",
            "X-Trace": "abc"
        ])
        #expect(merged["Accept"] == "application/vnd.synapse+json")
        #expect(merged["X-Trace"] == "abc")
    }

    @Test
    func bodyIsCarriedThroughForPost() {
        let payload = Data("{\"name\":\"a\"}".utf8)
        let endpoint = Endpoint<Echo>(method: .post, path: "items", body: payload)
        #expect(endpoint.method == .post)
        #expect(endpoint.body == payload)
    }
}
