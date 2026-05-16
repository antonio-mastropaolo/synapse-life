import Foundation

/// Typed deep-link routes for the Synnapse apps. The URL scheme is
/// `synnapse://<host>[/<segment>]?[query]`. Hosts map 1:1 to top-level
/// surfaces; the trailing path segment carries the optional record id
/// where applicable.
///
/// Parsing is pure and `Sendable` so it can run from any actor — the
/// scene-restoration path on macOS dispatches deep links from a
/// background queue, and we don't want to bottleneck on the main
/// actor for what is fundamentally string-shaping work.
public enum DeepLink: Equatable, Hashable, Sendable {

    public enum FinanceSurface: String, CaseIterable, Sendable, Equatable, Hashable {
        case personal, accounts, transactions, investments, work
    }

    case spotlight(query: String?)
    case approvals(id: String?)
    case finance(FinanceSurface)
    case life
    case people(id: String?)
    case inbox(messageId: String?)
    case advisors(id: String?)
    case sequences(id: String?)
    case octagon(vendor: String?)
    case settings

    // MARK: - Parsing

    /// The canonical Synnapse URL scheme. Centralised so the share
    /// extensions, hotkey handlers, and CI link-validators all read
    /// from the same source of truth.
    public static let scheme = "synnapse"

    /// Parses a URL into a typed `DeepLink`. Returns `nil` for any URL
    /// outside the `synnapse://` scheme or with an unrecognised host.
    public static func parse(url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // `URL.host` is more permissive than `URLComponents.host` for
        // custom schemes on older OSes; either works for the kinds of
        // values we accept, but parsing through `URLComponents` lets
        // us reach the query items without an extra round-trip.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else {
            return nil
        }

        // `path` always begins with "/" when present; strip it before
        // splitting so we don't end up with a leading empty segment.
        let path = components.path
        let firstSegment: String? = {
            guard path.hasPrefix("/") else { return path.isEmpty ? nil : path }
            let trimmed = String(path.dropFirst())
            guard !trimmed.isEmpty else { return nil }
            return trimmed.split(separator: "/").first.map(String.init)
        }()

        switch host {
        case "spotlight":
            let q = components.queryItems?.first { $0.name == "q" }?.value
            return .spotlight(query: q?.isEmpty == true ? nil : q)

        case "approvals":
            return .approvals(id: firstSegment)

        case "finance":
            guard let raw = firstSegment, let surface = FinanceSurface(rawValue: raw) else {
                return nil
            }
            return .finance(surface)

        case "life":
            return .life

        case "people":
            return .people(id: firstSegment)

        case "inbox":
            return .inbox(messageId: firstSegment)

        case "advisors":
            return .advisors(id: firstSegment)

        case "sequences":
            return .sequences(id: firstSegment)

        case "octagon":
            return .octagon(vendor: firstSegment)

        case "settings":
            return .settings

        default:
            return nil
        }
    }

    // MARK: - Serialisation

    /// Builds the canonical URL for this link. Always parses cleanly
    /// back through `parse(url:)`.
    public var url: URL {
        var components = URLComponents()
        components.scheme = DeepLink.scheme

        switch self {
        case .spotlight(let query):
            components.host = "spotlight"
            if let query, !query.isEmpty {
                components.queryItems = [URLQueryItem(name: "q", value: query)]
            }

        case .approvals(let id):
            components.host = "approvals"
            if let id, !id.isEmpty { components.path = "/" + id }

        case .finance(let surface):
            components.host = "finance"
            components.path = "/" + surface.rawValue

        case .life:
            components.host = "life"

        case .people(let id):
            components.host = "people"
            if let id, !id.isEmpty { components.path = "/" + id }

        case .inbox(let id):
            components.host = "inbox"
            if let id, !id.isEmpty { components.path = "/" + id }

        case .advisors(let id):
            components.host = "advisors"
            if let id, !id.isEmpty { components.path = "/" + id }

        case .sequences(let id):
            components.host = "sequences"
            if let id, !id.isEmpty { components.path = "/" + id }

        case .octagon(let vendor):
            components.host = "octagon"
            if let vendor, !vendor.isEmpty { components.path = "/" + vendor }

        case .settings:
            components.host = "settings"
        }

        // `URLComponents.url` only fails when scheme/host produce an
        // invalid combination. We control both, so the force-unwrap is
        // a contract assertion — but Swift 6 strict mode flags it, so
        // we fall back to a synthetic URL string instead.
        return components.url ?? URL(
            string: "\(DeepLink.scheme)://\(components.host ?? "settings")"
        ) ?? URL(fileURLWithPath: "/")
    }
}
