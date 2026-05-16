import Foundation

/// User-tunable preference keys persisted to `UserDefaults`. We model these
/// as typed accessors instead of `@AppStorage` so the M9 settings view
/// model is testable without a SwiftUI host.
///
/// Per memory `feedback_remote_no_commit`: this preference layer never
/// auto-persists to a remote pipeline. Everything is local-device only.
public enum SettingsKey: String, CaseIterable {
    case apiBaseURL = "synnapse.settings.apiBaseURL"
    case concealBalances = "synnapse.settings.concealBalances"
    case reduceMotionPreview = "synnapse.settings.reduceMotionPreview"
    case spotlightHotkey = "synnapse.settings.spotlightHotkey"
}

/// Pure-value snapshot of every setting. Equatable so the test suite can
/// diff state transitions.
public struct SettingsSnapshot: Sendable, Equatable {
    public var apiBaseURL: String
    public var concealBalances: Bool
    public var reduceMotionPreview: Bool
    public var spotlightHotkey: String

    public init(
        apiBaseURL: String = "",
        concealBalances: Bool = false,
        reduceMotionPreview: Bool = false,
        spotlightHotkey: String = "Cmd + Shift + Space"
    ) {
        self.apiBaseURL = apiBaseURL
        self.concealBalances = concealBalances
        self.reduceMotionPreview = reduceMotionPreview
        self.spotlightHotkey = spotlightHotkey
    }
}

/// Storage abstraction over UserDefaults so tests can inject a clean
/// suite without polluting `.standard`.
public protocol SettingsStore: Sendable {
    func read() -> SettingsSnapshot
    func write(_ snapshot: SettingsSnapshot)
}

/// Default UserDefaults-backed implementation. Defaults to `.standard`; tests
/// pass an isolated suite.
///
/// `UserDefaults` is documented as thread-safe but its Objective-C class is
/// not `Sendable`-annotated. We mark the store `@unchecked Sendable` and
/// keep all access through the public API so the unchecked promise stays
/// auditable — every read/write goes through one of two methods.
public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func read() -> SettingsSnapshot {
        SettingsSnapshot(
            apiBaseURL: defaults.string(forKey: SettingsKey.apiBaseURL.rawValue) ?? "",
            concealBalances: defaults.bool(forKey: SettingsKey.concealBalances.rawValue),
            reduceMotionPreview: defaults.bool(forKey: SettingsKey.reduceMotionPreview.rawValue),
            spotlightHotkey: defaults.string(forKey: SettingsKey.spotlightHotkey.rawValue)
                ?? "Cmd + Shift + Space"
        )
    }

    public func write(_ snapshot: SettingsSnapshot) {
        defaults.set(snapshot.apiBaseURL, forKey: SettingsKey.apiBaseURL.rawValue)
        defaults.set(snapshot.concealBalances, forKey: SettingsKey.concealBalances.rawValue)
        defaults.set(snapshot.reduceMotionPreview, forKey: SettingsKey.reduceMotionPreview.rawValue)
        defaults.set(snapshot.spotlightHotkey, forKey: SettingsKey.spotlightHotkey.rawValue)
    }
}

/// In-memory store, used by previews + tests that need to dodge the
/// `UserDefaults` global.
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: SettingsSnapshot

    public init(initial: SettingsSnapshot = SettingsSnapshot()) {
        self.snapshot = initial
    }

    public func read() -> SettingsSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    public func write(_ next: SettingsSnapshot) {
        lock.lock(); defer { lock.unlock() }
        snapshot = next
    }
}
