import Foundation

/// Server-issued session. `accessToken` is the bearer presented to the API on
/// every request; `refreshToken` is exchanged for a new pair when the access
/// token expires. Both tokens live in the Keychain (see `SessionStore`); only
/// `userId` and `expiresAt` are safe to read from a freshly-decoded envelope.
public struct Session: Codable, Sendable, Equatable {
    public let userId: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(userId: String, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}
