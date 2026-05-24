import Foundation

/// Typed deep-link routes for the Synapse apps. The URL scheme is
/// `synapse://<host>[/<segment>]?[query]`. Hosts map 1:1 to top-level
/// surfaces; the trailing path segment carries the optional record id
/// where applicable.
///
/// Parsing is pure and `Sendable` so it can run from any actor — the
/// scene-restoration path on macOS dispatches deep links from a
/// background queue, and we don't want to bottleneck on the main
/// actor for what is fundamentally string-shaping work.
///
/// Scope: Synapse is a private-life client. The work-flavoured hosts
/// (`spotlight`, `approvals`, `people`, `inbox`, `sequences`,
/// `octagon`, and `finance/work`) intentionally do not exist here —
/// those surfaces live in the synapse-v2 web app, not this client.
public enum DeepLink: Equatable, Hashable, Sendable {

    public enum FinanceSurface: String, CaseIterable, Sendable, Equatable, Hashable {
        case personal, accounts, transactions, investments
    }

    case finance(FinanceSurface)
    case activity
    case advisors(id: String?)
    case settings

    // MARK: - Parsing

    /// The canonical Synapse URL scheme. Centralised so the share
    /// extensions, hotkey handlers, and CI link-validators all read
    /// from the same source of truth.
    public static let scheme = "synapse"

    /// Parses a URL into a typed `DeepLink`. Returns `nil` for any URL
    /// outside the `synapse://` scheme or with an unrecognised host.
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
        case "finance":
            guard let raw = firstSegment, let surface = FinanceSurface(rawValue: raw) else {
                return nil
            }
            return .finance(surface)

        case "activity":
            return .activity

        case "advisors":
            return .advisors(id: firstSegment)

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
        case .finance(let surface):
            components.host = "finance"
            components.path = "/" + surface.rawValue

        case .activity:
            components.host = "activity"

        case .advisors(let id):
            components.host = "advisors"
            if let id, !id.isEmpty { components.path = "/" + id }

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
