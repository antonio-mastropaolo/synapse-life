import Foundation
import Testing
@testable import Models
@testable import Auth
@testable import Features

/// `signInForDebugBypass()` exists only under `#if DEBUG`. The whole suite
/// is gated the same way so a release-mode `swift test` doesn't try to
/// call a symbol that isn't compiled in. The release-mode coverage gap is
/// intentional: a release build is exactly the build that must NOT carry
/// the bypass, and reaching for it from a test would defeat the gate. The
/// shipping-build assertion ("symbol absent") is encoded in the gate
/// itself — if DEBUG were ever removed from this method's declaration,
/// the public release surface would change and a downstream caller (the
/// SignInView button below) would refuse to compile.
#if DEBUG

/// Keychain access requires entitlements that the iOS simulator host does
/// not grant; tests that persist a session are skipped there. The
/// pure-state-machine assertion still runs everywhere because it
/// inspects the in-memory `state` before touching the store.
#if targetEnvironment(simulator) && os(iOS)
private let keychainAvailable = false
#else
private let keychainAvailable = true
#endif

@Suite("AuthViewModel.signInForDebugBypass")
struct DebugBypassTests {

    @Test @MainActor
    func bypassProducesDeterministicSession() {
        let session = Session.debugBypass()
        #expect(session.userId == "debug-user")
        #expect(session.accessToken == "debug-access")
        #expect(session.refreshToken == "debug-refresh")
        // `Session.debugBypass` anchors expiresAt to a fixed UTC instant
        // (2100-01-01T00:00:00Z). Any clock that the test runs against
        // today is comfortably before it, which is the only property the
        // app actually cares about.
        #expect(session.expiresAt > Date())
    }

    @Test(.enabled(if: keychainAvailable)) @MainActor
    func bypassTransitionsSignedOutToSignedIn() async {
        let api = MockSessionAPI()
        let store = SessionStore(service: "tech.synnapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        #expect(vm.state == .signedOut)
        await vm.signInForDebugBypass()

        if case .signedIn(let session) = vm.state {
            #expect(session == Session.debugBypass())
        } else {
            Issue.record("expected signedIn after bypass, got \(vm.state)")
        }
    }

    @Test(.enabled(if: keychainAvailable)) @MainActor
    func bypassPersistsThroughSessionStore() async {
        let api = MockSessionAPI()
        let store = SessionStore(service: "tech.synnapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        await vm.signInForDebugBypass()
        let persisted = await store.current()
        #expect(persisted == Session.debugBypass())
    }

    @Test @MainActor
    func bypassDoesNotTouchTheNetworkAPI() async {
        // The mock API records the last identity token it saw on the wire.
        // The bypass must NOT exchange anything — it builds the session
        // locally — so the recorded token stays nil.
        let api = MockSessionAPI()
        let store = SessionStore(service: "tech.synnapse.tests.\(UUID().uuidString)")
        defer { Task { try? await store.clear() } }
        let vm = AuthViewModel(api: api, store: store)

        await vm.signInForDebugBypass()
        let lastToken = await api.lastIdentityToken
        #expect(lastToken == nil)
    }
}

#endif
