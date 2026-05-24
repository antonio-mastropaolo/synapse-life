import Foundation
import Testing
@testable import Auth
@testable import Models

// SessionStore is a thin wrapper over `SecItem*`. On the iOS simulator that
// surface requires an entitled host app; see `KeychainStoreTests` for the
// same gate. Tests that touch keychain are skipped there.
#if targetEnvironment(simulator) && os(iOS)
private let keychainAvailable = false
#else
private let keychainAvailable = true
#endif

@Suite("SessionStore")
struct SessionStoreTests {

    private func uniqueService() -> String {
        "tech.synapse.session.tests.\(UUID().uuidString)"
    }

    private func makeSession(expiresInSeconds: TimeInterval = 3600) -> Session {
        Session(
            userId: "user-123",
            accessToken: "access-abc",
            refreshToken: "refresh-xyz",
            expiresAt: Date(timeIntervalSinceNow: expiresInSeconds)
        )
    }

    @Test(.enabled(if: keychainAvailable))
    func roundTripsSession() async throws {
        let store = SessionStore(service: uniqueService())
        defer { Task { try? await store.clear() } }
        let s = makeSession()
        try await store.save(s)
        let read = await store.current()
        #expect(read?.userId == "user-123")
        #expect(read?.accessToken == "access-abc")
        #expect(read?.refreshToken == "refresh-xyz")
        // Date round-trips through JSON with sub-second loss tolerable.
        if let read {
            #expect(abs(read.expiresAt.timeIntervalSince(s.expiresAt)) < 0.01)
        }
    }

    @Test(.enabled(if: keychainAvailable))
    func clearRemovesBothTokensFromKeychain() async throws {
        let service = uniqueService()
        let store = SessionStore(service: service)
        try await store.save(makeSession())
        try await store.clear()
        let read = await store.current()
        #expect(read == nil)

        // And both raw keychain accounts are gone — defense against a future
        // refactor that "succeeds" by only deleting the envelope.
        let raw = KeychainStore(service: service)
        #expect(try raw.get(account: "session.access") == nil)
        #expect(try raw.get(account: "session.refresh") == nil)
    }

    @Test(.enabled(if: keychainAvailable))
    func isAuthenticatedRequiresUnexpiredSession() async throws {
        let store = SessionStore(service: uniqueService())
        defer { Task { try? await store.clear() } }

        // Fresh session → authenticated.
        try await store.save(makeSession(expiresInSeconds: 600))
        var authed = await store.isAuthenticated()
        #expect(authed == true)

        // Expired session → not authenticated, even if present.
        try await store.save(makeSession(expiresInSeconds: -60))
        authed = await store.isAuthenticated()
        #expect(authed == false)
    }

    @Test
    func absentSessionMeansNotAuthenticated() async throws {
        let store = SessionStore(service: uniqueService())
        let authed = await store.isAuthenticated()
        #expect(authed == false)
    }
}
