import Foundation
import Models
import Networking

public enum SessionAPIError: Error, Equatable, Sendable {
    /// Returned by `LiveSessionAPI` when `serverContractLive` is false. The
    /// synapse-v2 server does not yet expose a `/api/auth/apple/exchange`
    /// route; this flag exists so the client can be wired end-to-end today
    /// and the live path can flip on the day the server lands.
    case serverEndpointNotYetImplemented
    case decoding
    case server(status: Int)
    case transport
}

public protocol SessionAPI: Sendable {
    func exchangeAppleIdentityToken(
        _ token: Data,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> Session

    func refresh(_ refreshToken: String) async throws -> Session

    /// Apple Guideline 5.1.1(v) — apps that allow account creation must
    /// also allow account deletion from within the app. The caller is
    /// expected to clear the local keychain regardless of whether this
    /// call succeeds; this method only addresses server-side data.
    func deleteAccount(accessToken: String) async throws
}

/// Live SessionAPI. The request/response shape below is what the server will
/// need to expose. Today the server has no such route — the
/// `serverContractLive` flag defaults to `false` so production builds throw
/// `.serverEndpointNotYetImplemented` until the route ships.
///
/// Expected contract (proposed for synapse-v2):
///   POST /api/auth/apple/exchange
///     body: { identityToken: base64-string, fullName?: PersonNameComponents,
///             email?: string }
///     response: { userId, accessToken, refreshToken, expiresAt: iso-8601 }
///   POST /api/auth/refresh
///     body: { refreshToken: string }
///     response: same as above
///   POST /api/auth/delete
///     headers: Authorization: Bearer <accessToken>
///     response: 204 No Content on success
public struct LiveSessionAPI: SessionAPI {
    private let baseURL: URL
    private let session: URLSession
    private let serverContractLive: Bool

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        serverContractLive: Bool = false
    ) {
        self.baseURL = baseURL
        self.session = session
        self.serverContractLive = serverContractLive
    }

    public func exchangeAppleIdentityToken(
        _ token: Data,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> Session {
        guard serverContractLive else { throw SessionAPIError.serverEndpointNotYetImplemented }
        let body = ExchangeBody(
            identityToken: token.base64EncodedString(),
            fullName: fullName.map(NameBody.init),
            email: email
        )
        let request = try makeRequest(path: "/api/auth/apple/exchange", body: body)
        return try await perform(request)
    }

    public func refresh(_ refreshToken: String) async throws -> Session {
        guard serverContractLive else { throw SessionAPIError.serverEndpointNotYetImplemented }
        let body = RefreshBody(refreshToken: refreshToken)
        let request = try makeRequest(path: "/api/auth/refresh", body: body)
        return try await perform(request)
    }

    public func deleteAccount(accessToken: String) async throws {
        guard serverContractLive else { throw SessionAPIError.serverEndpointNotYetImplemented }
        guard let url = URL(string: "api/auth/delete", relativeTo: baseURL) else {
            throw SessionAPIError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw SessionAPIError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw SessionAPIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionAPIError.server(status: http.statusCode)
        }
    }

    // MARK: - Wire types

    private struct ExchangeBody: Encodable, Sendable {
        let identityToken: String
        let fullName: NameBody?
        let email: String?
    }

    private struct NameBody: Encodable, Sendable {
        let givenName: String?
        let familyName: String?
        let middleName: String?
        let namePrefix: String?
        let nameSuffix: String?
        let nickname: String?

        init(_ pnc: PersonNameComponents) {
            self.givenName = pnc.givenName
            self.familyName = pnc.familyName
            self.middleName = pnc.middleName
            self.namePrefix = pnc.namePrefix
            self.nameSuffix = pnc.nameSuffix
            self.nickname = pnc.nickname
        }
    }

    private struct RefreshBody: Encodable, Sendable {
        let refreshToken: String
    }

    private struct SessionDTO: Decodable, Sendable {
        let userId: String
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    // MARK: - Plumbing

    private func makeRequest<B: Encodable>(path: String, body: B) throws -> URLRequest {
        guard let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL) else {
            throw SessionAPIError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Session {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SessionAPIError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw SessionAPIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionAPIError.server(status: http.statusCode)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { d in
                let c = try d.singleValueContainer()
                let raw = try c.decode(String.self)
                let withFrac = ISO8601DateFormatter()
                withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let v = withFrac.date(from: raw) { return v }
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let v = plain.date(from: raw) { return v }
                throw DecodingError.dataCorruptedError(
                    in: c,
                    debugDescription: "Unparseable ISO-8601 date: \(raw)"
                )
            }
            let dto = try decoder.decode(SessionDTO.self, from: data)
            return Session(
                userId: dto.userId,
                accessToken: dto.accessToken,
                refreshToken: dto.refreshToken,
                expiresAt: dto.expiresAt
            )
        } catch {
            throw SessionAPIError.decoding
        }
    }
}

/// In-memory mock for tests and previews.
public actor MockSessionAPI: SessionAPI {
    private var nextSession: Session?
    private var nextError: Error?
    private var nextDeleteError: Error?
    public private(set) var lastIdentityToken: Data?
    public private(set) var lastRefreshToken: String?
    public private(set) var lastDeleteAccessToken: String?

    public init() {}

    public func setNextSession(_ session: Session) {
        self.nextSession = session
        self.nextError = nil
    }

    public func setNextError(_ error: Error) {
        self.nextError = error
    }

    public func setNextDeleteError(_ error: Error) {
        self.nextDeleteError = error
    }

    public func exchangeAppleIdentityToken(
        _ token: Data,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> Session {
        lastIdentityToken = token
        if let err = nextError { throw err }
        guard let s = nextSession else { throw SessionAPIError.transport }
        return s
    }

    public func refresh(_ refreshToken: String) async throws -> Session {
        lastRefreshToken = refreshToken
        if let err = nextError { throw err }
        guard let s = nextSession else { throw SessionAPIError.transport }
        return s
    }

    public func deleteAccount(accessToken: String) async throws {
        lastDeleteAccessToken = accessToken
        if let err = nextDeleteError {
            nextDeleteError = nil
            throw err
        }
    }
}
