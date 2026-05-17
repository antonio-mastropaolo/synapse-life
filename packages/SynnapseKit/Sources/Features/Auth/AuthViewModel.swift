import Foundation
import Observation
import Models
import Auth

public enum AuthState: Sendable, Equatable {
    case signedOut
    case signingIn
    case signedIn(Session)
    case error(String)
}

@MainActor
@Observable
public final class AuthViewModel {

    public private(set) var state: AuthState = .signedOut

    private let api: SessionAPI
    private let store: SessionStore
    private let handler: SignInWithAppleHandler

    public init(
        api: SessionAPI,
        store: SessionStore,
        handler: SignInWithAppleHandler = SignInWithAppleHandler()
    ) {
        self.api = api
        self.store = store
        self.handler = handler
    }

    /// Rehydrates `state` from the keychain on launch. Call once at app start.
    public func restoreFromStore() async {
        if let session = await store.current(), session.expiresAt > Date() {
            state = .signedIn(session)
        } else {
            state = .signedOut
        }
    }

    public func signIn(with credential: AppleCredentialLike) async {
        state = .signingIn
        do {
            let result = try handler.handle(credential)
            let session = try await api.exchangeAppleIdentityToken(
                result.identityToken,
                fullName: result.fullName,
                email: result.email
            )
            try await store.save(session)
            state = .signedIn(session)
        } catch let appleError as AppleSignInError {
            state = .error(String(describing: appleError))
        } catch let apiError as SessionAPIError {
            state = .error(String(describing: apiError))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func signOut() async {
        try? await store.clear()
        state = .signedOut
    }

    #if DEBUG
    /// DEBUG-only escape hatch. The unsigned local builds can't present the
    /// real Apple sheet, and the synapse-v2 server has no
    /// `/api/auth/apple/exchange` route yet — so the app would otherwise be
    /// unreachable on a developer machine. This synthesizes a deterministic
    /// `Session` and routes it through the same `SessionStore` the live
    /// path uses, so downstream surfaces see a fully-formed signed-in
    /// state. Never compiled into release builds.
    public func signInForDebugBypass() async {
        let session = Session.debugBypass()
        try? await store.save(session)
        state = .signedIn(session)
    }
    #endif
}

#if DEBUG
extension Session {
    /// Deterministic fixture used by [[signInForDebugBypass]]. Kept on the
    /// type so tests can assert exact field values without touching
    /// AuthViewModel internals.
    public static func debugBypass() -> Session {
        Session(
            userId: "debug-user",
            accessToken: "debug-access",
            refreshToken: "debug-refresh",
            // ~100 years out; far enough that no realistic test clock
            // crosses it. Held in UTC so the value is identical on every
            // host.
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
    }
}
#endif
