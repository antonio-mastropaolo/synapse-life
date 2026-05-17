import SwiftUI
import DesignSystem
import Auth

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Cross-platform sign-in screen. Hosts Apple's `SignInWithAppleButton` and
/// exposes a callback path so snapshot tests can render the same surface
/// without spinning up the real `AuthorizationController`.
@MainActor
public struct SignInView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Owner-supplied tap handler. For the real flow this calls into
    /// `AuthViewModel.signIn(with:)` with the credential the AS framework
    /// hands back. For previews/snapshots, it stays a no-op.
    private let onTapSignIn: () -> Void

    /// Optional handler invoked when `SignInWithAppleButton` finishes. The
    /// real app wires this to `AuthViewModel.signIn(with:)`. Snapshot tests
    /// don't exercise the button itself; we still rely on `onTapSignIn` so
    /// that the legacy preview path stays callable.
    private let onComplete: ((Result<AppleSignInResultPayload, Error>) -> Void)?

    /// DEBUG-only handler for the secondary "Continue without signing in"
    /// button. Wired to `AuthViewModel.signInForDebugBypass()` in the app
    /// shell. Snapshot tests pass nil so the bypass row stays absent in
    /// reference images.
    private let onTapDebugBypass: (() -> Void)?

    /// Optional error string surfaced under the buttons. The shell passes
    /// `AuthViewModel.state`'s `.error(reason)` payload here so the user
    /// sees what went wrong instead of staring at a silent button.
    private let errorMessage: String?

    public init(
        onTapSignIn: @escaping () -> Void = {},
        onComplete: ((Result<AppleSignInResultPayload, Error>) -> Void)? = nil,
        onTapDebugBypass: (() -> Void)? = nil,
        errorMessage: String? = nil
    ) {
        self.onTapSignIn = onTapSignIn
        self.onComplete = onComplete
        self.onTapDebugBypass = onTapDebugBypass
        self.errorMessage = errorMessage
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ZStack {
            tokens.background.color.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                wordmark(tokens: tokens)
                Text("Sign in to continue")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                VStack(spacing: 12) {
                    signInButton(tokens: tokens)
                        .frame(maxWidth: 320)
                    #if DEBUG
                    debugBypassRow(tokens: tokens)
                    #endif
                    errorRow(tokens: tokens)
                }
                Spacer()
                footer(tokens: tokens)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
        }
        .accessibilityElement(children: .contain)
    }

    private func wordmark(tokens: TokenSet) -> some View {
        VStack(spacing: 4) {
            Text("Synapse")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(theme.identity.rawValue)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func errorRow(tokens: TokenSet) -> some View {
        if let message = errorMessage, !message.isEmpty {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .accessibilityLabel("Sign-in error: \(message)")
        }
    }

    #if DEBUG
    @ViewBuilder
    private func debugBypassRow(tokens: TokenSet) -> some View {
        if let onTapDebugBypass {
            VStack(spacing: 2) {
                Button("Continue without signing in (debug)", action: onTapDebugBypass)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHint("Skips Apple sign-in and seeds a local debug session.")
                Text("Debug build — bypass available")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
            }
        }
    }
    #endif

    @ViewBuilder
    private func signInButton(tokens: TokenSet) -> some View {
        #if canImport(AuthenticationServices)
        SignInWithAppleButton(
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
                onTapSignIn()
            },
            onCompletion: { result in
                switch result {
                case .success(let auth):
                    if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                        let payload = AppleSignInResultPayload(credential: credential)
                        onComplete?(.success(payload))
                    } else {
                        onComplete?(.failure(AppleSignInError.missingIdentityToken))
                    }
                case .failure(let error):
                    onComplete?(.failure(error))
                }
            }
        )
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 48)
        #else
        Button(action: onTapSignIn) {
            Text("Sign in with Apple")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(tokens.background.color)
                .background(tokens.foregroundPrimary.color)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        #endif
    }

    private func footer(tokens: TokenSet) -> some View {
        Text("Local-only build. No telemetry.")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
    }
}

/// Wraps `ASAuthorizationAppleIDCredential` so callers don't have to import
/// `AuthenticationServices` to read the result. Conforms to
/// `AppleCredentialLike` so it can be fed directly into `AuthViewModel`.
public struct AppleSignInResultPayload: AppleCredentialLike {
    public let user: String
    public let identityToken: Data?
    public let email: String?
    public let fullName: PersonNameComponents?

    #if canImport(AuthenticationServices)
    public init(credential: ASAuthorizationAppleIDCredential) {
        self.user = credential.user
        self.identityToken = credential.identityToken
        self.email = credential.email
        self.fullName = credential.fullName
    }
    #endif

    public init(
        user: String,
        identityToken: Data?,
        email: String?,
        fullName: PersonNameComponents?
    ) {
        self.user = user
        self.identityToken = identityToken
        self.email = email
        self.fullName = fullName
    }
}
