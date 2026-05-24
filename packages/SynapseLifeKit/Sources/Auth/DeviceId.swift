import Foundation

/// Stable per-device identifier persisted in the Keychain. The synapse-v2
/// auth contract requires a `deviceId` field on every Sign-in-with-Apple
/// exchange so the server can scope a session to a single device (so a
/// stolen JWT cannot be replayed from a different host).
///
/// The id is generated lazily on first read and cached. Because it lives in
/// the Keychain — and because the shipping target sets a shared
/// `keychain-access-groups` entitlement — all four bundle ids
/// (`tech.synapse.life.{ios,mac}`, `tech.synapse.work.{ios,mac}`) read the
/// same value when installed on the same device, which lets the server
/// reconcile "this human, four apps" without an extra device-link flow.
///
/// Resilience: if the Keychain refuses the call (unentitled `swift test`
/// host, simulator without keychain-access-groups, etc.), the provider
/// falls back to a process-scoped UUID. That fallback is deliberately
/// non-persistent — the next process gets a fresh id — because pretending
/// to persist when we cannot is worse than honestly rotating.
public struct DeviceIdProvider: Sendable {

    public static let defaultAccount = "deviceId"
    public static let defaultService = "tech.synapse.device"

    private let store: KeychainStore
    private let account: String

    public init(
        service: String = DeviceIdProvider.defaultService,
        accessGroup: String? = KeychainStore.sharedAccessGroup,
        account: String = DeviceIdProvider.defaultAccount
    ) {
        self.store = KeychainStore(
            service: service,
            accessibility: KeychainStore.defaultAccessibility,
            accessGroup: accessGroup
        )
        self.account = account
    }

    /// Returns the persisted id, minting and storing a fresh UUID the first
    /// time. Failures to persist degrade silently to a process-local UUID;
    /// callers always get a non-empty string.
    public func current() -> String {
        if let existing = (try? store.get(account: account)) ?? nil, !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        // Best-effort persist. If the keychain rejects the write, we still
        // hand the caller a valid value for this process.
        try? store.set(fresh, account: account)
        return fresh
    }
}
