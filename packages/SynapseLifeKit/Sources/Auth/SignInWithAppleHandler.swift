import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Test-shaped seam over `ASAuthorizationAppleIDCredential`. We only need the
/// four fields the server cares about; modeling them as a protocol means tests
/// don't need to fabricate a real `ASAuthorizationAppleIDCredential` (which
/// can't be safely instantiated outside the AuthorizationController flow).
public protocol AppleCredentialLike {
    var user: String { get }
    var identityToken: Data? { get }
    var email: String? { get }
    var fullName: PersonNameComponents? { get }
}

#if canImport(AuthenticationServices)
extension ASAuthorizationAppleIDCredential: AppleCredentialLike {}
#endif

public struct AppleSignInResult: Sendable, Equatable {
    public let userId: String
    public let identityToken: Data
    /// One-time authorization code Apple returns alongside the identity
    /// token. Optional — the server uses it to verify the assertion
    /// server-side, but the identity-token-only path also works.
    public let authorizationCode: Data?
    public let email: String?
    public let fullName: PersonNameComponents?
}

public enum AppleSignInError: Error, Equatable, Sendable {
    case missingIdentityToken
    /// Returned by the coordinator when `AuthenticationServices` reports a
    /// cancellation / decline. Tests still get the granular
    /// `ASAuthorizationError.Code` via `.cancelled(let raw)` where the
    /// raw value is the localized description.
    case cancelled(String)
    case unknown(String)
}

/// Pure value-shaper. Given a credential, validates the required fields and
/// projects them into an `AppleSignInResult`. The live coordinator below
/// drives the AuthenticationServices flow and feeds the credential through
/// this handler.
public struct SignInWithAppleHandler: Sendable {
    public init() {}

    public func handle(_ credential: AppleCredentialLike) throws -> AppleSignInResult {
        guard let token = credential.identityToken else {
            throw AppleSignInError.missingIdentityToken
        }
        // The legacy `AppleCredentialLike` protocol doesn't expose the
        // authorization code (it was added later by the AppleAuth contract).
        // Coordinator subclasses pass the richer credential type via
        // `handleExtended`; the legacy path returns `authorizationCode: nil`
        // and stays source-compatible.
        return AppleSignInResult(
            userId: credential.user,
            identityToken: token,
            authorizationCode: nil,
            email: credential.email,
            fullName: credential.fullName
        )
    }

    #if canImport(AuthenticationServices)
    /// Variant that retains the one-time `authorizationCode` Apple sets on
    /// the real `ASAuthorizationAppleIDCredential`. Used by the live
    /// coordinator; legacy call sites keep using `handle(_:)`.
    public func handleExtended(_ credential: ASAuthorizationAppleIDCredential) throws -> AppleSignInResult {
        guard let token = credential.identityToken else {
            throw AppleSignInError.missingIdentityToken
        }
        return AppleSignInResult(
            userId: credential.user,
            identityToken: token,
            authorizationCode: credential.authorizationCode,
            email: credential.email,
            fullName: credential.fullName
        )
    }
    #endif
}

#if canImport(AuthenticationServices)

/// Live Sign-in-with-Apple driver. Wires `ASAuthorizationController` to a
/// Swift Concurrency continuation so callers can `await coordinator.signIn()`
/// from view-model code without exposing AS delegates.
///
/// `@MainActor` because every AS call must happen on the main thread, and
/// because the coordinator retains a continuation that the AS delegate
/// callbacks resolve from delegate-thread context.
@MainActor
public final class SignInWithAppleCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private let handler: SignInWithAppleHandler
    /// Held while a request is in flight; nil otherwise. The continuation
    /// is resumed exactly once from either delegate callback.
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    public init(handler: SignInWithAppleHandler = SignInWithAppleHandler()) {
        self.handler = handler
    }

    /// Starts a Sign-in-with-Apple request. The continuation resolves when
    /// the system sheet completes (`success`) or is dismissed (`failure`).
    /// Concurrent calls are serialized by the actor isolation; a second
    /// `signIn()` blocks until the first resolves.
    public func signIn() async throws -> AppleSignInResult {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil }
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.missingIdentityToken)
            return
        }
        do {
            let result = try handler.handleExtended(cred)
            continuation?.resume(returning: result)
        } catch {
            continuation?.resume(throwing: error)
        }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { continuation = nil }
        if let asError = error as? ASAuthorizationError {
            switch asError.code {
            case .canceled:
                continuation?.resume(throwing: AppleSignInError.cancelled(asError.localizedDescription))
            default:
                continuation?.resume(throwing: AppleSignInError.unknown(asError.localizedDescription))
            }
        } else {
            continuation?.resume(throwing: AppleSignInError.unknown(error.localizedDescription))
        }
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

#endif
