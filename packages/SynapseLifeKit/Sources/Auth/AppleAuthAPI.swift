import Foundation
import Models

/// New synapse-v2 Sign-in-with-Apple contract.
///
///   POST <baseURL>/api/auth/apple
///     body: {
///       identityToken: String,             // base64-encoded JWT from Apple
///       authorizationCode: String?,        // one-time code (optional)
///       fullName: { givenName, familyName }?,
///       email: String?,
///       deviceId: String,
///       platform: "ios" | "macos",
///       appBundleId: String
///     }
///     200: { jwt: String, expiresAt: String /* ISO-8601 */, userId: String }
///     401: { error: String, message: String }
///
///   POST <baseURL>/api/account/delete
///     headers: Authorization: Bearer <jwt>
///     200: { ok: Bool, deletedAt: String /* ISO-8601 */ }
///
/// This is a sibling of [[LiveSessionAPI]] — the older route
/// (`/api/auth/apple/exchange`) is preserved for backwards compatibility
/// with code already using `Session.refreshToken`. The new contract is
/// single-JWT (no refresh), so `Session.refreshToken` is left empty when
/// converting the response back into a `Session` value.
public enum AppleAuthAPIError: Error, Equatable, Sendable {
    case decoding
    case server(status: Int, message: String?)
    case transport
    case unauthorized(message: String?)
}

public enum ApplePlatform: String, Sendable {
    case ios
    case macos

    /// Resolves the platform the running binary is on. Kept as a static so
    /// callers don't have to thread the choice through every layer.
    public static func current() -> ApplePlatform {
        #if os(iOS) || targetEnvironment(macCatalyst)
        return .ios
        #else
        return .macos
        #endif
    }
}

public struct AppleAuthRequest: Sendable, Equatable {
    public let identityToken: String
    public let authorizationCode: String?
    public let givenName: String?
    public let familyName: String?
    public let email: String?
    public let deviceId: String
    public let platform: ApplePlatform
    public let appBundleId: String

    public init(
        identityToken: String,
        authorizationCode: String?,
        givenName: String?,
        familyName: String?,
        email: String?,
        deviceId: String,
        platform: ApplePlatform,
        appBundleId: String
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
        self.deviceId = deviceId
        self.platform = platform
        self.appBundleId = appBundleId
    }
}

public struct AppleAuthResponse: Sendable, Equatable {
    public let jwt: String
    public let expiresAt: Date
    public let userId: String

    public init(jwt: String, expiresAt: Date, userId: String) {
        self.jwt = jwt
        self.expiresAt = expiresAt
        self.userId = userId
    }

    /// Convert into the in-package `Session` value. The new contract
    /// does not return a refresh token; we store an empty string so the
    /// existing `SessionStore` envelope keeps round-tripping cleanly.
    public func toSession() -> Session {
        Session(
            userId: userId,
            accessToken: jwt,
            refreshToken: "",
            expiresAt: expiresAt
        )
    }
}

public protocol AppleAuthAPI: Sendable {
    func signInWithApple(_ request: AppleAuthRequest) async throws -> AppleAuthResponse
    /// Calls `/api/account/delete` with the supplied bearer token. Returns
    /// the server-reported deletion timestamp on success.
    func deleteAccount(jwt: String) async throws -> Date
}

public struct LiveAppleAuthAPI: AppleAuthAPI {
    private let baseURL: URL
    private let urlSession: URLSession

    public init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func signInWithApple(_ request: AppleAuthRequest) async throws -> AppleAuthResponse {
        let body = RequestBody(
            identityToken: request.identityToken,
            authorizationCode: request.authorizationCode,
            fullName: (request.givenName != nil || request.familyName != nil)
                ? NameBody(givenName: request.givenName, familyName: request.familyName)
                : nil,
            email: request.email,
            deviceId: request.deviceId,
            platform: request.platform.rawValue,
            appBundleId: request.appBundleId
        )
        let urlRequest = try makeRequest(path: "/api/auth/apple", body: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw AppleAuthAPIError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw AppleAuthAPIError.transport }
        if http.statusCode == 401 {
            let err = try? Self.decoder().decode(ErrorBody.self, from: data)
            throw AppleAuthAPIError.unauthorized(message: err?.message)
        }
        guard (200..<300).contains(http.statusCode) else {
            let err = try? Self.decoder().decode(ErrorBody.self, from: data)
            throw AppleAuthAPIError.server(status: http.statusCode, message: err?.message)
        }
        do {
            let dto = try Self.decoder().decode(ResponseDTO.self, from: data)
            return AppleAuthResponse(jwt: dto.jwt, expiresAt: dto.expiresAt, userId: dto.userId)
        } catch {
            throw AppleAuthAPIError.decoding
        }
    }

    public func deleteAccount(jwt: String) async throws -> Date {
        guard let url = URL(string: "api/account/delete", relativeTo: baseURLWithTrailingSlash()) else {
            throw AppleAuthAPIError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AppleAuthAPIError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw AppleAuthAPIError.transport }
        if http.statusCode == 401 {
            let err = try? Self.decoder().decode(ErrorBody.self, from: data)
            throw AppleAuthAPIError.unauthorized(message: err?.message)
        }
        guard (200..<300).contains(http.statusCode) else {
            let err = try? Self.decoder().decode(ErrorBody.self, from: data)
            throw AppleAuthAPIError.server(status: http.statusCode, message: err?.message)
        }
        do {
            let dto = try Self.decoder().decode(DeleteResponseDTO.self, from: data)
            guard dto.ok else {
                throw AppleAuthAPIError.server(status: http.statusCode, message: "ok=false")
            }
            return dto.deletedAt
        } catch is AppleAuthAPIError {
            throw AppleAuthAPIError.server(status: http.statusCode, message: "ok=false")
        } catch {
            throw AppleAuthAPIError.decoding
        }
    }

    // MARK: - Wire types

    private struct RequestBody: Encodable, Sendable {
        let identityToken: String
        let authorizationCode: String?
        let fullName: NameBody?
        let email: String?
        let deviceId: String
        let platform: String
        let appBundleId: String
    }

    private struct NameBody: Encodable, Sendable {
        let givenName: String?
        let familyName: String?
    }

    private struct ResponseDTO: Decodable, Sendable {
        let jwt: String
        let expiresAt: Date
        let userId: String
    }

    private struct DeleteResponseDTO: Decodable, Sendable {
        let ok: Bool
        let deletedAt: Date
    }

    private struct ErrorBody: Decodable, Sendable {
        let error: String?
        let message: String?
    }

    // MARK: - Plumbing

    private func baseURLWithTrailingSlash() -> URL {
        if baseURL.absoluteString.hasSuffix("/") { return baseURL }
        return URL(string: baseURL.absoluteString + "/") ?? baseURL
    }

    private func makeRequest<B: Encodable>(path: String, body: B) throws -> URLRequest {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: trimmed, relativeTo: baseURLWithTrailingSlash()) else {
            throw AppleAuthAPIError.transport
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

    private static func decoder() -> JSONDecoder {
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
        return decoder
    }
}
