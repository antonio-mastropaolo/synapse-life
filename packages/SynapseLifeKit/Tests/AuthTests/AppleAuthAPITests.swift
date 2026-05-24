import Foundation
import Testing
@testable import Auth
@testable import Models
@testable import Networking

@Suite("AppleAuthAPI")
struct AppleAuthAPITests {

    private let baseURL = URL(string: "https://api.synapse.test/")!

    private func request() -> AppleAuthRequest {
        AppleAuthRequest(
            identityToken: "id-tok",
            authorizationCode: "auth-code",
            givenName: "Antonio",
            familyName: "Mastropaolo",
            email: "a@example.com",
            deviceId: "device-abc",
            platform: .ios,
            appBundleId: "tech.synapse.life.ios"
        )
    }

    @Test
    func signInPostsExpectedShape() async throws {
        let urlSession = URLProtocolStub.makeSession { _ in
            let body = """
            {
              "jwt": "tok-123",
              "expiresAt": "2030-01-01T00:00:00.000Z",
              "userId": "001.deadbeef"
            }
            """.data(using: .utf8)!
            return .success(URLProtocolStub.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(urlSession) }

        let api = LiveAppleAuthAPI(baseURL: baseURL, urlSession: urlSession)
        let response = try await api.signInWithApple(request())

        #expect(response.jwt == "tok-123")
        #expect(response.userId == "001.deadbeef")

        let recorded = try #require(URLProtocolStub.requests(for: urlSession).first)
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url?.path == "/api/auth/apple")

        let bodyData = Self.bodyData(from: recorded)
        let json = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(json["identityToken"] as? String == "id-tok")
        #expect(json["authorizationCode"] as? String == "auth-code")
        #expect(json["email"] as? String == "a@example.com")
        #expect(json["deviceId"] as? String == "device-abc")
        #expect(json["platform"] as? String == "ios")
        #expect(json["appBundleId"] as? String == "tech.synapse.life.ios")
        let name = try #require(json["fullName"] as? [String: Any])
        #expect(name["givenName"] as? String == "Antonio")
        #expect(name["familyName"] as? String == "Mastropaolo")
    }

    @Test
    func signInSurfacesUnauthorizedWithMessage() async throws {
        let urlSession = URLProtocolStub.makeSession { _ in
            let body = """
            { "error": "invalid_token", "message": "expired identity token" }
            """.data(using: .utf8)!
            return .success(URLProtocolStub.Response(
                statusCode: 401,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(urlSession) }
        let api = LiveAppleAuthAPI(baseURL: baseURL, urlSession: urlSession)
        await #expect(throws: AppleAuthAPIError.unauthorized(message: "expired identity token")) {
            _ = try await api.signInWithApple(request())
        }
    }

    @Test
    func deleteAccountReturnsDeletedAtAndSendsBearer() async throws {
        let urlSession = URLProtocolStub.makeSession { _ in
            let body = """
            { "ok": true, "deletedAt": "2026-05-24T12:00:00.000Z" }
            """.data(using: .utf8)!
            return .success(URLProtocolStub.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(urlSession) }
        let api = LiveAppleAuthAPI(baseURL: baseURL, urlSession: urlSession)
        let deletedAt = try await api.deleteAccount(jwt: "tok-xyz")
        #expect(deletedAt.timeIntervalSince1970 > 0)

        let recorded = try #require(URLProtocolStub.requests(for: urlSession).first)
        #expect(recorded.url?.path == "/api/account/delete")
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.value(forHTTPHeaderField: "Authorization") == "Bearer tok-xyz")
    }

    @Test
    func responseRoundTripsIntoSession() {
        let response = AppleAuthResponse(
            jwt: "jjj",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            userId: "u-1"
        )
        let session = response.toSession()
        #expect(session.userId == "u-1")
        #expect(session.accessToken == "jjj")
        #expect(session.refreshToken == "")
        #expect(session.expiresAt.timeIntervalSince1970 == 2_000_000_000)
    }

    // URLSession strips httpBody when sent through URLProtocol; pull from the
    // body stream when needed. Mirrors the same helper in SessionAPITests.
    private static func bodyData(from request: URLRequest) -> Data {
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
    }
}
