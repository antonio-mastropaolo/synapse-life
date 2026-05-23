import Foundation
import Models

/// Where a streaming prompt is going to be answered. The router picks
/// `appleIntelligence` only when the on-device `Foundation Models`
/// framework is available (macOS 15+ / iOS 18+), otherwise falls back
/// to `server`. The branch is observable from outside so a host can
/// surface a "Powered by Apple Intelligence" or "Server" label.
public enum IntelligenceRoute: String, Sendable, Hashable {
    case appleIntelligence
    case server
}

/// A token-emitting source. Identical wire shape to `AskDelta` so
/// either branch can plug into the same view code.
public enum IntelligenceDelta: Sendable, Hashable {
    case text(String)
    case done
    case error(String)
}

/// Abstraction over "where the answer comes from" — the on-device
/// Apple Intelligence path or the server path. The implementation
/// picks the route lazily so the host can keep one VM regardless of
/// runtime OS.
public protocol IntelligenceRouter: Sendable {
    /// Synchronous route decision. Hosts use this to paint a small
    /// route label next to the streaming answer.
    var route: IntelligenceRoute { get }

    /// Stream a free-form answer. Implementations are responsible for
    /// honoring `Task.cancellation` and finishing the continuation.
    func stream(
        prompt: String,
        context: AskContext
    ) -> AsyncThrowingStream<IntelligenceDelta, Error>
}

/// Default router. At construction we decide which branch the device
/// is on; the branch is fixed for the lifetime of the router so the
/// view label doesn't flicker.
///
/// `forceRoute` is the test seam — pass `.appleIntelligence` or
/// `.server` to exercise the corresponding branch deterministically.
public struct DefaultIntelligenceRouter: IntelligenceRouter {
    private let primary: IntelligenceRouter
    public let route: IntelligenceRoute

    /// Production initializer. Decides at runtime whether the
    /// on-device path is available; if not, falls back to the server
    /// router (which wraps an `AskAPI`).
    public init(
        appleIntelligence: IntelligenceRouter,
        server: IntelligenceRouter,
        forceRoute: IntelligenceRoute? = nil
    ) {
        let decision: IntelligenceRoute
        if let forced = forceRoute {
            decision = forced
        } else {
            decision = Self.systemPicksAppleIntelligence() ? .appleIntelligence : .server
        }
        self.route = decision
        self.primary = (decision == .appleIntelligence) ? appleIntelligence : server
    }

    public func stream(
        prompt: String,
        context: AskContext
    ) -> AsyncThrowingStream<IntelligenceDelta, Error> {
        return primary.stream(prompt: prompt, context: context)
    }

    /// Public so tests can assert what the runtime picked. The actual
    /// `Foundation Models` import lives behind an `#if canImport`
    /// guard inside the AppleIntelligenceRouter implementation; this
    /// helper only checks the OS version availability.
    public static func systemPicksAppleIntelligence() -> Bool {
        if #available(macOS 15, iOS 18, *) {
            return true
        }
        return false
    }
}

/// Apple Intelligence branch. Wraps the on-device `Foundation Models`
/// framework when it's importable; otherwise constructs a "not
/// available" stream that hands the error back to the caller (the
/// `DefaultIntelligenceRouter` should not pick this branch when
/// availability says no).
///
/// We intentionally do not `import FoundationModels` here yet — the
/// framework name is provisional pending the OS GA, and SwiftPM
/// targets that don't ship it would fail to compile. Instead we
/// expose the abstraction; the macOS app layer can subclass /
/// reimplement when the framework lands.
public struct AppleIntelligenceRouter: IntelligenceRouter {
    public let route: IntelligenceRoute = .appleIntelligence
    private let underlying: any IntelligenceRouter

    public init(underlying: any IntelligenceRouter) {
        self.underlying = underlying
    }

    public func stream(
        prompt: String,
        context: AskContext
    ) -> AsyncThrowingStream<IntelligenceDelta, Error> {
        return underlying.stream(prompt: prompt, context: context)
    }
}

/// Server / web branch. Wraps any `AskAPI` (live or stub) and adapts
/// `AskDelta` -> `IntelligenceDelta` 1:1.
public struct ServerIntelligenceRouter: IntelligenceRouter {
    public let route: IntelligenceRoute = .server
    private let askAPI: AskAPI

    public init(askAPI: AskAPI) {
        self.askAPI = askAPI
    }

    public func stream(
        prompt: String,
        context: AskContext
    ) -> AsyncThrowingStream<IntelligenceDelta, Error> {
        let inner = askAPI.ask(question: prompt, context: context)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in inner {
                        if Task.isCancelled { break }
                        switch delta {
                        case .text(let s): continuation.yield(.text(s))
                        case .done:        continuation.yield(.done)
                        case .error(let m): continuation.yield(.error(m))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
