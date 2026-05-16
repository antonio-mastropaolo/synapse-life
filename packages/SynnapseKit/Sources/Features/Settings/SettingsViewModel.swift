import Foundation
import Observation

/// Drives the Settings surface. Pure-Swift; the SwiftUI bridge binds
/// directly to these mutable properties.
///
/// Persistence is synchronous through a [[SettingsStore]] — UserDefaults
/// reads and writes are cheap enough that we don't bother batching. Each
/// setter writes back immediately so the macOS Settings scene's reactive
/// previews work without an explicit "Apply" button.
@MainActor
@Observable
public final class SettingsViewModel {

    public var apiBaseURL: String {
        didSet { persist() }
    }
    public var concealBalances: Bool {
        didSet { persist() }
    }
    public var reduceMotionPreview: Bool {
        didSet { persist() }
    }
    public var spotlightHotkey: String {
        didSet { persist() }
    }

    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
        let snapshot = store.read()
        self.apiBaseURL = snapshot.apiBaseURL
        self.concealBalances = snapshot.concealBalances
        self.reduceMotionPreview = snapshot.reduceMotionPreview
        self.spotlightHotkey = snapshot.spotlightHotkey
    }

    public var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            apiBaseURL: apiBaseURL,
            concealBalances: concealBalances,
            reduceMotionPreview: reduceMotionPreview,
            spotlightHotkey: spotlightHotkey
        )
    }

    /// Validates that `apiBaseURL` parses as an absolute URL. The macOS
    /// Settings scene uses this to colour the field red and disable
    /// dependent UI when the operator types garbage.
    public var apiBaseURLIsValid: Bool {
        if apiBaseURL.isEmpty { return true } // empty falls back to default
        guard let url = URL(string: apiBaseURL), let scheme = url.scheme else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    /// Reset every key to its default. The integrator wires this to a
    /// "Reset to defaults" button on the macOS settings scene.
    public func resetToDefaults() {
        let defaults = SettingsSnapshot()
        apiBaseURL = defaults.apiBaseURL
        concealBalances = defaults.concealBalances
        reduceMotionPreview = defaults.reduceMotionPreview
        spotlightHotkey = defaults.spotlightHotkey
    }

    private func persist() {
        store.write(snapshot)
    }
}
