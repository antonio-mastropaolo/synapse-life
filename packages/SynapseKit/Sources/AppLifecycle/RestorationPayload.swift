import Foundation

/// State the app rehydrates on launch. Every field is optional so an
/// older app version can decode a newer payload (forward-compat) and a
/// newer app can decode a payload from before the field existed
/// (backward-compat).
public struct RestorationPayload: Codable, Sendable, Equatable {

    public struct WindowSize: Codable, Sendable, Equatable {
        public let width: Double
        public let height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public var sidebarSelection: String?
    public var macWindow: WindowSize?
    public var iosLastTab: String?
    public var financeSurface: String?

    public init(
        sidebarSelection: String? = nil,
        macWindow: WindowSize? = nil,
        iosLastTab: String? = nil,
        financeSurface: String? = nil
    ) {
        self.sidebarSelection = sidebarSelection
        self.macWindow = macWindow
        self.iosLastTab = iosLastTab
        self.financeSurface = financeSurface
    }

    /// Explicit `CodingKeys` so a future rename doesn't silently break
    /// existing stored payloads. Codable's default behaviour ignores
    /// keys not listed here, which is exactly the forward-compat
    /// contract we want.
    private enum CodingKeys: String, CodingKey {
        case sidebarSelection
        case macWindow
        case iosLastTab
        case financeSurface
    }
}

/// Actor-isolated store backed by `UserDefaults`. Lives on its own
/// actor so concurrent saves from the scene-phase delegate and the
/// hotkey path can't tear the encoded payload.
///
/// `UserDefaults` is documented thread-safe but is not annotated
/// `Sendable`, so the actor takes a `Sendable` *description* (a suite
/// name) rather than a live `UserDefaults` object. Production code
/// uses the default suite by leaving `suiteName` nil; tests pass a
/// UUID-scoped suite so they don't collide with the real store.
public actor RestorationStore {

    public static let defaultKey = "synapse.restoration.v1"

    /// `UserDefaults` access is funnelled through this `@unchecked
    /// Sendable` wrapper so the actor can hold the reference without
    /// tripping strict-concurrency diagnostics.
    private struct DefaultsBox: @unchecked Sendable {
        let defaults: UserDefaults
    }

    private let box: DefaultsBox
    private let key: String

    public init(suiteName: String? = nil, key: String = RestorationStore.defaultKey) {
        let resolved: UserDefaults = {
            if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
                return suite
            }
            return .standard
        }()
        self.box = DefaultsBox(defaults: resolved)
        self.key = key
    }

    public func save(_ payload: RestorationPayload) {
        do {
            let data = try JSONEncoder().encode(payload)
            box.defaults.set(data, forKey: key)
        } catch {
            // A failed encode is non-fatal — losing restoration is
            // strictly preferable to crashing on launch. The next
            // save will overwrite the (now-stale) blob.
        }
    }

    public func load() -> RestorationPayload? {
        guard let data = box.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RestorationPayload.self, from: data)
    }

    public func clear() {
        box.defaults.removeObject(forKey: key)
    }
}
