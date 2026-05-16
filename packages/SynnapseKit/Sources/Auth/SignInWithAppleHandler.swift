import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
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
    public let email: String?
    public let fullName: PersonNameComponents?
}

public enum AppleSignInError: Error, Equatable, Sendable {
    case missingIdentityToken
}

public struct SignInWithAppleHandler: Sendable {
    public init() {}

    public func handle(_ credential: AppleCredentialLike) throws -> AppleSignInResult {
        guard let token = credential.identityToken else {
            throw AppleSignInError.missingIdentityToken
        }
        return AppleSignInResult(
            userId: credential.user,
            identityToken: token,
            email: credential.email,
            fullName: credential.fullName
        )
    }
}
