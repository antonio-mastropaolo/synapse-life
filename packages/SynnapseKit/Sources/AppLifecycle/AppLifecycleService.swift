import Foundation
import Observation

/// Central place that wires deep-link dispatch into the shells without
/// either of them having to know about the other's surface structure.
/// The shell owns the service, registers a `route` callback at bootstrap,
/// and feeds in URLs from `.onOpenURL` (iOS) or `application(_:open:)`
/// (macOS).
///
/// Restoration is also funnelled through here so the iOS scene-phase
/// delegate and the macOS `NSWindow` save state callbacks land in the
/// same persistence pipeline.
@MainActor
@Observable
public final class AppLifecycleService {

    public typealias RouteHandler = @Sendable @MainActor (DeepLink) -> Void

    public let restoration: RestorationStore
    private var handler: RouteHandler?

    /// Most-recently-resolved deep link. Surfaced for diagnostics and
    /// for tests that don't want to install a handler.
    public private(set) var lastResolvedLink: DeepLink?

    public init(restoration: RestorationStore = RestorationStore()) {
        self.restoration = restoration
    }

    public func setRouteHandler(_ handler: @escaping RouteHandler) {
        self.handler = handler
    }

    /// Routes a URL through the registered handler. Returns the parsed
    /// `DeepLink` so callers can decide whether to suppress a default
    /// behaviour (for example, AppKit's default open-document path).
    @discardableResult
    public func handle(url: URL) -> DeepLink? {
        guard let link = DeepLink.parse(url: url) else { return nil }
        lastResolvedLink = link
        handler?(link)
        return link
    }

    public func loadRestoration() async -> RestorationPayload? {
        await restoration.load()
    }

    public func saveRestoration(_ payload: RestorationPayload) async {
        await restoration.save(payload)
    }

    public func clearRestoration() async {
        await restoration.clear()
    }
}
