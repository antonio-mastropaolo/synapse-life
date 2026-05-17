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
    public var aiModel: String {
        didSet { persist() }
    }
    public var aiOnDeviceTranscription: Bool {
        didSet { persist() }
    }
    public var aiInsightsDigest: Bool {
        didSet { persist() }
    }
    public var aiAnomalySensitivity: Int {
        didSet { persist() }
    }

    /// Choices for the model picker. The user's auto-memory pins
    /// load-bearing calls to `claude-opus-4-7`; the other entries are
    /// surfaced for transparency, not as a cheaper fallback.
    public static let aiModelChoices: [String] = [
        "claude-opus-4-7",
        "claude-sonnet-4-6",
        "claude-haiku-4-5"
    ]

    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
        let snapshot = store.read()
        self.apiBaseURL = snapshot.apiBaseURL
        self.concealBalances = snapshot.concealBalances
        self.reduceMotionPreview = snapshot.reduceMotionPreview
        self.aiModel = snapshot.aiModel
        self.aiOnDeviceTranscription = snapshot.aiOnDeviceTranscription
        self.aiInsightsDigest = snapshot.aiInsightsDigest
        self.aiAnomalySensitivity = snapshot.aiAnomalySensitivity
    }

    public var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            apiBaseURL: apiBaseURL,
            concealBalances: concealBalances,
            reduceMotionPreview: reduceMotionPreview,
            aiModel: aiModel,
            aiOnDeviceTranscription: aiOnDeviceTranscription,
            aiInsightsDigest: aiInsightsDigest,
            aiAnomalySensitivity: aiAnomalySensitivity
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
        aiModel = defaults.aiModel
        aiOnDeviceTranscription = defaults.aiOnDeviceTranscription
        aiInsightsDigest = defaults.aiInsightsDigest
        aiAnomalySensitivity = defaults.aiAnomalySensitivity
    }

    private func persist() {
        store.write(snapshot)
    }
}
