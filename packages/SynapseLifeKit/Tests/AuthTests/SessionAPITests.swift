import Foundation
import Testing
@testable import Auth
@testable import Models
@testable import Networking

@Suite("SessionAPI")
struct SessionAPITests {

    private let baseURL = URL(string: "https://synapse.test/")!

    @Test
    func exchangeBuildsCorrectRequest() async throws {
        let session = URLProtocolStub.makeSession { _ in
            let body = """
            {
              "userId": "001.deadbeef",
              "accessToken": "acc",
              "refreshToken": "ref",
              "expiresAt": "2030-01-01T00:00:00.000Z"
            }
            """.data(using: .utf8)!
            return .success(URLProtocolStub.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSessionAPI(
            baseURL: baseURL,
            session: session,
            serverContractLive: true
        )
        let token = Data([0xAA, 0xBB])
        var name = PersonNameComponents()
        name.givenName = "A"
        let result = try await api.exchangeAppleIdentityToken(
            token,
            fullName: name,
            email: "a@example.com"
        )

        #expect(result.userId == "001.deadbeef")
        #expect(result.accessToken == "acc")
        #expect(result.refreshToken == "ref")

        let requests = URLProtocolStub.requests(for: session)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/auth/apple/exchange")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        // URLSession strips the body when sent through URLProtocol; the
        // body is on httpBodyStream. Pull it back out either way.
        let bodyData: Data = {
            if let b = request.httpBody { return b }
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = Data()
                let chunk = 1024
                var bytes = [UInt8](repeating: 0, count: chunk)
                while stream.hasBytesAvailable {
                    let read = stream.read(&bytes, maxLength: chunk)
                    if read <= 0 { break }
                    buffer.append(bytes, count: read)
                }
                return buffer
            }
            return Data()
        }()

        let json = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(json["identityToken"] as? String == token.base64EncodedString())
        #expect(json["email"] as? String == "a@example.com")
        if let nameJSON = json["fullName"] as? [String: Any] {
            #expect(nameJSON["givenName"] as? String == "A")
        } else {
            Issue.record("expected fullName in body, got \(json)")
        }
    }

    @Test
    func stubbedLiveAPIThrowsNotImplementedWhenFlagOff() async throws {
        let session = URLProtocolStub.makeSession { _ in
            return .success(URLProtocolStub.Response(statusCode: 200))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveSessionAPI(
            baseURL: baseURL,
            session: session,
            serverContractLive: false
        )
        await #expect(throws: SessionAPIError.serverEndpointNotYetImplemented) {
            _ = try await api.exchangeAppleIdentityToken(Data([0x00]), fullName: nil, email: nil)
        }
    }

    @Test
    func deleteAccountBuildsCorrectRequest() async throws {
        let session = URLProtocolStub.makeSession { _ in
            return .success(URLProtocolStub.Response(
                statusCode: 204,
                headers: [:],
                body: Data()
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveSessionAPI(
            baseURL: baseURL,
            session: session,
            serverContractLive: true
        )
        try await api.deleteAccount(accessToken: "acc-1")
        let request = try #require(URLProtocolStub.requests(for: session).first)
        #expect(request.url?.path == "/api/auth/delete")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer acc-1")
    }

    @Test
    func deleteAccountThrowsNotImplementedWhenFlagOff() async throws {
        let session = URLProtocolStub.makeSession { _ in
            return .success(URLProtocolStub.Response(statusCode: 200))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveSessionAPI(
            baseURL: baseURL,
            session: session,
            serverContractLive: false
        )
        await #expect(throws: SessionAPIError.serverEndpointNotYetImplemented) {
            try await api.deleteAccount(accessToken: "acc")
        }
    }

    @Test
    func deleteAccountSurfacesServerFailure() async throws {
        let session = URLProtocolStub.makeSession { _ in
            return .success(URLProtocolStub.Response(statusCode: 500))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveSessionAPI(
            baseURL: baseURL,
            session: session,
            serverContractLive: true
        )
        await #expect(throws: SessionAPIError.server(status: 500)) {
            try await api.deleteAccount(accessToken: "acc")
        }
    }

    @Test
    func refreshBuildsCorrectRequest() async throws {
        let session = URLProtocolStub.makeSession { _ in
            let body = """
            {
              "userId": "u",
              "accessToken": "acc2",
              "refreshToken": "ref2",
              "expiresAt": "2030-01-01T00:00:00.000Z"
            }
            """.data(using: .utf8)!
            return .success(URLProtocolStub.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveSessionAPI(
            baseURL: baseURL,
            session: session,
            serverContractLive: true
        )
        _ = try await api.refresh("rt-1")
        let request = try #require(URLProtocolStub.requests(for: session).first)
        #expect(request.url?.path == "/api/auth/refresh")
        #expect(request.httpMethod == "POST")
    }
}
