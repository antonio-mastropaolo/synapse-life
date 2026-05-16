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
}
