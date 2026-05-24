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
    /// Canonical Sign-in-with-Apple endpoint per the synapse-v2 contract
    /// (`POST /api/auth/apple`). When non-nil, `signIn(with:)` posts here
    /// and stores the returned JWT through `SessionStore`. The legacy
    /// `SessionAPI.exchangeAppleIdentityToken` path is preserved for the
    /// refresh-token flow and for older test wiring; new callers should
    /// pass an `AppleAuthAPI` and let it own the sign-in path.
    private let appleAuth: AppleAuthAPI?
    private let store: SessionStore
    private let handler: SignInWithAppleHandler
    /// Stable per-device id. Sent on every Sign-in-with-Apple request so
    /// the server can scope a session to one device.
    private let deviceId: DeviceIdProvider
    /// Bundle id the server uses to tell life-iOS from life-mac from
    /// work-iOS from work-mac. Resolved lazily so test wiring can inject
    /// a fixed value without depending on the host bundle.
    private let appBundleId: () -> String

    public init(
        api: SessionAPI,
        store: SessionStore,
        appleAuth: AppleAuthAPI? = nil,
        handler: SignInWithAppleHandler = SignInWithAppleHandler(),
        deviceId: DeviceIdProvider = DeviceIdProvider(),
        appBundleId: @escaping () -> String = { Bundle.main.bundleIdentifier ?? "tech.synapse.life" }
    ) {
        self.api = api
        self.store = store
        self.appleAuth = appleAuth
        self.handler = handler
        self.deviceId = deviceId
        self.appBundleId = appBundleId
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
            let session: Session
            if let appleAuth {
                // Canonical synapse-v2 contract path.
                let request = AppleAuthRequest(
                    identityToken: result.identityToken.base64EncodedString(),
                    authorizationCode: result.authorizationCode?.base64EncodedString(),
                    givenName: result.fullName?.givenName,
                    familyName: result.fullName?.familyName,
                    email: result.email,
                    deviceId: deviceId.current(),
                    platform: ApplePlatform.current(),
                    appBundleId: appBundleId()
                )
                let response = try await appleAuth.signInWithApple(request)
                session = response.toSession()
            } else {
                // Legacy `exchangeAppleIdentityToken` path.
                session = try await api.exchangeAppleIdentityToken(
                    result.identityToken,
                    fullName: result.fullName,
                    email: result.email
                )
            }
            try await store.save(session)
            state = .signedIn(session)
        } catch let appleError as AppleSignInError {
            state = .error(String(describing: appleError))
        } catch let appleAPIError as AppleAuthAPIError {
            state = .error(String(describing: appleAPIError))
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

    /// Apple Guideline 5.1.1(v). Best-effort server delete, then always
    /// clears the keychain and drops state to `.signedOut`. The local
    /// clear happens regardless of server outcome so a user offline at
    /// the moment of deletion still leaves no credentials on device.
    ///
    /// When wired with an `AppleAuthAPI` (the canonical synapse-v2 path),
    /// the call targets `POST /api/account/delete`. The legacy fall-through
    /// hits `SessionAPI.deleteAccount`.
    public func deleteAccount() async {
        if case .signedIn(let session) = state {
            if let appleAuth {
                _ = try? await appleAuth.deleteAccount(jwt: session.accessToken)
            } else {
                try? await api.deleteAccount(accessToken: session.accessToken)
            }
        }
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
