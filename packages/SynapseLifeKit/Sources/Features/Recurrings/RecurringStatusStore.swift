import Foundation

/// Per-merchant user action on a detected recurring: `confirmed`
/// (user agrees this is a real recurring charge), `ignored` (user has
/// told us to stop surfacing it — e.g. a one-off Affirm payment the
/// detector treated as monthly), or `detected` (initial, no user
/// action yet). The store is UserDefaults-backed so the user's
/// decisions survive a relaunch.
///
/// Mirrors [[CategoryStore]] in shape so the Recurrings surface can
/// follow the same Confirm / Ignore button pattern the Categories
/// surface uses for rule confirmation.
public enum RecurringStatus: String, Sendable, Codable {
    case detected
    case confirmed
    case ignored
}

@MainActor
public protocol RecurringStatusStoreProtocol: AnyObject, Sendable {
    func status(for merchant: String) -> RecurringStatus
    func setStatus(_ status: RecurringStatus, for merchant: String)
}

@MainActor
public final class RecurringStatusStore: RecurringStatusStoreProtocol {

    private let defaults: UserDefaults
    private let key: String
    private var cache: [String: RecurringStatus]

    public init(defaults: UserDefaults = .standard, key: String = "synapse.recurrings.status.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: RecurringStatus].self, from: data) {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }

    public func status(for merchant: String) -> RecurringStatus {
        cache[normalize(merchant)] ?? .detected
    }

    public func setStatus(_ status: RecurringStatus, for merchant: String) {
        let key = normalize(merchant)
        if status == .detected {
            cache.removeValue(forKey: key)
        } else {
            cache[key] = status
        }
        persist()
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: key)
        }
    }
}

/// In-memory store for previews / tests so a snapshot doesn't pollute
/// the user's `UserDefaults` and so unit tests can pre-seed state.
@MainActor
public final class InMemoryRecurringStatusStore: RecurringStatusStoreProtocol {
    private var store: [String: RecurringStatus] = [:]

    public init(initial: [String: RecurringStatus] = [:]) {
        self.store = initial.reduce(into: [:]) { acc, kv in
            acc[kv.key.lowercased()] = kv.value
        }
    }

    public func status(for merchant: String) -> RecurringStatus {
        store[merchant.lowercased()] ?? .detected
    }

    public func setStatus(_ status: RecurringStatus, for merchant: String) {
        store[merchant.lowercased()] = status
    }
}
