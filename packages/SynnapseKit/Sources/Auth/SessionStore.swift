import Foundation
import Models

/// Persists the user `Session` in two Keychain entries (access + refresh tokens)
/// alongside a small JSON envelope that carries the non-secret metadata
/// (`userId`, `expiresAt`). Tokens are read+written as separate items so a
/// future rotation step can mutate one without rewriting the other.
///
/// Actor isolation: Keychain reads/writes are technically thread-safe via
/// `SecItem*`, but we wrap them anyway so callers (`AuthViewModel`,
/// `APIClient.AuthInterceptor`) have a clean `await` contract and we can add
/// in-process caching later without changing the call site.
public actor SessionStore {

    public static let defaultService = "tech.synnapse.session"
    public static let accessAccount = "session.access"
    public static let refreshAccount = "session.refresh"
    public static let envelopeAccount = "session.envelope"

    private let keychain: KeychainStore

    public init(service: String = SessionStore.defaultService) {
        self.keychain = KeychainStore(service: service)
    }

    /// Envelope is keyed by Unix epoch seconds (sub-millisecond) rather than
    /// stringified ISO-8601 so the round-trip preserves fractional precision
    /// without relying on `JSONEncoder`'s `.iso8601` strategy (which drops
    /// fractional seconds and would cause `expiresAt` to drift by up to ~1s
    /// after a save+read cycle).
    private struct Envelope: Codable, Sendable {
        let userId: String
        let expiresAtEpoch: Double
    }

    public func current() async -> Session? {
        do {
            guard
                let access = try keychain.get(account: Self.accessAccount),
                let refresh = try keychain.get(account: Self.refreshAccount),
                let envRaw = try keychain.get(account: Self.envelopeAccount),
                let envData = envRaw.data(using: .utf8)
            else { return nil }
            let env = try JSONDecoder().decode(Envelope.self, from: envData)
            return Session(
                userId: env.userId,
                accessToken: access,
                refreshToken: refresh,
                expiresAt: Date(timeIntervalSince1970: env.expiresAtEpoch)
            )
        } catch {
            return nil
        }
    }

    public func save(_ session: Session) async throws {
        let env = Envelope(
            userId: session.userId,
            expiresAtEpoch: session.expiresAt.timeIntervalSince1970
        )
        let envData = try JSONEncoder().encode(env)
        guard let envString = String(data: envData, encoding: .utf8) else {
            throw KeychainError.encodingFailure
        }
        try keychain.set(session.accessToken, account: Self.accessAccount)
        try keychain.set(session.refreshToken, account: Self.refreshAccount)
        try keychain.set(envString, account: Self.envelopeAccount)
    }

    public func clear() async throws {
        try keychain.delete(account: Self.accessAccount)
        try keychain.delete(account: Self.refreshAccount)
        try keychain.delete(account: Self.envelopeAccount)
    }

    public func isAuthenticated() async -> Bool {
        guard let session = await current() else { return false }
        return session.expiresAt > Date()
    }
}
