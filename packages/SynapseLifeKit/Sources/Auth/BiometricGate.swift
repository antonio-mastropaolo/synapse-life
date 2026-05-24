import Foundation
import Observation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Face ID / Touch ID / device-passcode gate guarding access to the app's
/// financial surfaces. The gate locks on cold launch and on
/// `scenePhase` → `.background` when the foreground duration exceeded
/// `backgroundLockThreshold` (default 60s). A successful biometric
/// evaluation unlocks until the next lock event.
///
/// The gate is platform-conditional: on hosts that lack `LocalAuthentication`
/// (Linux `swift test`, some CI containers) the API still exists but always
/// reports the gate as `unlocked` so feature code can compile and tests pass.
///
/// Pattern: the gate is `@Observable` and `@MainActor`; the app's root
/// scene observes `state` and overlays a lock view whenever it is `.locked`.
/// All authentication calls hop through `authenticate(reason:)`, which is
/// `async throws` and returns once the biometric prompt resolves.
@MainActor
@Observable
public final class BiometricGate {

    public enum State: Sendable, Equatable {
        case locked          // first launch, or returned from background after threshold
        case unlocking       // a `LAContext.evaluatePolicy` call is in-flight
        case unlocked        // user has authenticated this session
        case unavailable     // the host has no biometric or passcode capability
    }

    public enum GateError: Error, Sendable, Equatable {
        case unavailable                  // platform without LocalAuthentication
        case noPolicyAvailable(String?)   // device has no Face ID / Touch ID / passcode
        case userCancelled
        case userFallback
        case authenticationFailed
        case other(String)
    }

    /// How long the app can remain backgrounded before the gate snaps back
    /// to `.locked`. Tweakable per-deployment; the default mirrors common
    /// banking-app behavior.
    public let backgroundLockThreshold: TimeInterval

    /// Friendly reason string surfaced inside the system biometric sheet.
    /// Localizable; defaults to a neutral English phrase. Apps in non-en
    /// locales can pass a translated string.
    public let reason: String

    /// Current gate state. Reactive — SwiftUI re-renders on transition.
    public private(set) var state: State

    /// The most recent background event timestamp. Used by
    /// `noteForegrounded()` to decide whether to relock.
    private var backgroundedAt: Date?

    public init(
        backgroundLockThreshold: TimeInterval = 60,
        reason: String = "Unlock Synapse to view your finances."
    ) {
        self.backgroundLockThreshold = backgroundLockThreshold
        self.reason = reason
        #if canImport(LocalAuthentication)
        // The gate starts locked; the shell calls `authenticate()` after
        // its first `.task` runs. If the device cannot evaluate any policy
        // we transition to `.unavailable` and the shell renders without a
        // gate (the OS-level lockscreen is the sole gate in that case).
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
            self.state = .locked
        } else {
            self.state = .unavailable
        }
        #else
        self.state = .unavailable
        #endif
    }

    // MARK: - Lifecycle hooks (called by the shell)

    /// Called from `scenePhase` observer when the app enters background.
    public func noteBackgrounded(now: Date = Date()) {
        backgroundedAt = now
    }

    /// Called from `scenePhase` observer when the app returns to active.
    /// If the foreground gap exceeded `backgroundLockThreshold` and the
    /// gate is currently `.unlocked`, snap back to `.locked` so the shell
    /// presents the lock view again.
    public func noteForegrounded(now: Date = Date()) {
        guard state == .unlocked, let bg = backgroundedAt else {
            backgroundedAt = nil
            return
        }
        if now.timeIntervalSince(bg) >= backgroundLockThreshold {
            state = .locked
        }
        backgroundedAt = nil
    }

    // MARK: - Authentication

    /// Present the biometric / passcode sheet and resolve when the user
    /// answers. Throws `GateError` on failure or cancellation. On the
    /// `.unavailable` platform we treat the gate as permanently open
    /// (the OS lockscreen is the only effective gate).
    @discardableResult
    public func authenticate(reason: String? = nil) async throws -> Bool {
        switch state {
        case .unlocked, .unavailable:
            return true
        case .unlocking:
            // A concurrent call is already in flight; treat it as a no-op so
            // callers don't double-prompt. The first caller will flip the
            // state once it resolves.
            return false
        case .locked:
            break
        }

        #if canImport(LocalAuthentication)
        state = .unlocking
        let ctx = LAContext()
        var policyErr: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyErr) else {
            state = .unavailable
            throw GateError.noPolicyAvailable(policyErr?.localizedDescription)
        }
        let prompt = reason ?? self.reason
        do {
            let success = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: prompt
            )
            if success {
                state = .unlocked
                backgroundedAt = nil
                return true
            } else {
                state = .locked
                throw GateError.authenticationFailed
            }
        } catch let laError as LAError {
            state = .locked
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw GateError.userCancelled
            case .userFallback:
                throw GateError.userFallback
            case .authenticationFailed:
                throw GateError.authenticationFailed
            default:
                throw GateError.other(laError.localizedDescription)
            }
        } catch {
            state = .locked
            throw GateError.other(error.localizedDescription)
        }
        #else
        // Non-Apple platform — no gate to apply.
        state = .unavailable
        return true
        #endif
    }

    /// Factory for demo / preview / test wiring: returns a gate stuck at
    /// `.unavailable` so SwiftUI previews and `usesDemoData` launches do
    /// not surface a biometric prompt.
    public static func alwaysUnlocked() -> BiometricGate {
        let gate = BiometricGate()
        gate.state = .unavailable
        return gate
    }

    /// Force the gate back to `.locked`. Useful for sign-out flows and for
    /// the "Re-authenticate" button on the lock view itself.
    public func lock() {
        switch state {
        case .unavailable:
            return
        default:
            state = .locked
        }
    }
}
