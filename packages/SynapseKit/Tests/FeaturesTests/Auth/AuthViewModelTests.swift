import Foundation
import Testing
@testable import Models
@testable import Auth
@testable import Features

/// A no-op `AppleCredentialLike` that drives the handler in tests without
/// instantiating `ASAuthorizationAppleIDCredential`.
private struct TestCredential: AppleCredentialLike {
    let user: String
    let identityToken: Data?
    let email: String?
    let fullName: PersonNameComponents?
}

/// `AuthViewModel` persists through `SessionStore`, which on the iOS
/// simulator hits the entitlement wall (`errSecMissingEntitlement`). Gate
/// the keychain-touching tests there; the pure state-machine test
/// (`missingIdentityTokenSurfacesError`) doesn't reach the store and runs
/// everywhere.
#if targetEnvironment(simulator) && os(iOS)
private let keychainAvailable = false
#else
private let keychainAvailable = true
#endif

@Suite("AuthViewModel")
struct AuthViewModelTests {

    private func makeSession() -> Session {
        Session(
            userId: "u",
            accessToken: "acc",
            refreshToken: "ref",
            expiresAt: Date(timeIntervalSinceNow: 600)
        )
    }

    @Test(.enabled(if: keychainAvailable)) @MainActor
    func happyPathSignsIn() async throws {
        let api = MockSessionAPI()
        let session = makeSession()
        await api.setNextSession(session)
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        #expect(vm.state == .signedOut)
        let cred = TestCredential(
            user: "u",
            identityToken: Data([0x01]),
            email: "a@b",
            fullName: nil
        )
        await vm.signIn(with: cred)

        if case .signedIn(let s) = vm.state {
            #expect(s.userId == "u")
        } else {
            Issue.record("expected signedIn, got \(vm.state)")
        }
        // Persisted in keychain too.
        let read = await store.current()
        #expect(read?.userId == "u")
    }

    @Test @MainActor
    func failureBubblesError() async throws {
        let api = MockSessionAPI()
        await api.setNextError(SessionAPIError.serverEndpointNotYetImplemented)
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        let cred = TestCredential(
            user: "u",
            identityToken: Data([0x01]),
            email: nil,
            fullName: nil
        )
        await vm.signIn(with: cred)

        if case .error(let message) = vm.state {
            #expect(message.contains("not yet implemented") || message.contains("serverEndpointNotYetImplemented"))
        } else {
            Issue.record("expected error state, got \(vm.state)")
        }
    }

    @Test @MainActor
    func missingIdentityTokenSurfacesError() async throws {
        let api = MockSessionAPI()
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        let cred = TestCredential(
            user: "u",
            identityToken: nil,
            email: nil,
            fullName: nil
        )
        await vm.signIn(with: cred)

        if case .error = vm.state {} else {
            Issue.record("expected error state, got \(vm.state)")
        }
    }

    @Test(.enabled(if: keychainAvailable)) @MainActor
    func signOutClearsStateAndKeychain() async throws {
        let api = MockSessionAPI()
        await api.setNextSession(makeSession())
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        let cred = TestCredential(
            user: "u",
            identityToken: Data([0x01]),
            email: nil,
            fullName: nil
        )
        await vm.signIn(with: cred)
        await vm.signOut()
        #expect(vm.state == .signedOut)
        let read = await store.current()
        #expect(read == nil)
    }

    @Test(.enabled(if: keychainAvailable)) @MainActor
    func deleteAccountCallsServerAndClearsLocal() async throws {
        let api = MockSessionAPI()
        await api.setNextSession(makeSession())
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        let cred = TestCredential(
            user: "u",
            identityToken: Data([0x01]),
            email: nil,
            fullName: nil
        )
        await vm.signIn(with: cred)

        await vm.deleteAccount()

        #expect(vm.state == .signedOut)
        let read = await store.current()
        #expect(read == nil)
        let lastToken = await api.lastDeleteAccessToken
        #expect(lastToken == "acc")
    }

    @Test(.enabled(if: keychainAvailable)) @MainActor
    func deleteAccountClearsLocalEvenIfServerFails() async throws {
        let api = MockSessionAPI()
        await api.setNextSession(makeSession())
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        await vm.signIn(with: TestCredential(
            user: "u",
            identityToken: Data([0x01]),
            email: nil,
            fullName: nil
        ))

        await api.setNextDeleteError(SessionAPIError.server(status: 503))
        await vm.deleteAccount()

        #expect(vm.state == .signedOut)
        let read = await store.current()
        #expect(read == nil)
    }

    @Test @MainActor
    func deleteAccountWhileSignedOutIsNoOp() async throws {
        let api = MockSessionAPI()
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        await vm.deleteAccount()
        #expect(vm.state == .signedOut)
        let lastToken = await api.lastDeleteAccessToken
        #expect(lastToken == nil)
    }

    @Test
    func viewModelIsMainActor() async throws {
        // Compile-time assertion that init must hop to main.
        let api = MockSessionAPI()
        let store = SessionStore(service: "tech.synapse.tests.\(UUID().uuidString)")
        let vm = await MainActor.run { AuthViewModel(api: api, store: store) }
        let state = await MainActor.run { vm.state }
        #expect(state == .signedOut)
    }
}
