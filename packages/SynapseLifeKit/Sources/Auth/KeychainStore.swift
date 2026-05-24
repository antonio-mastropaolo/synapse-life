import Foundation
import Security

public enum KeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case encodingFailure
}

/// Minimal Keychain wrapper around `SecItem*` for refresh-token storage and
/// other small secrets. Items are scoped by `service` and `account`. The
/// default accessibility class is `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`
/// — strictly stronger than the previous `…AfterFirstUnlockThisDeviceOnly`
/// default — so secrets cannot be hosted on a device that lacks a passcode
/// and cannot leak via iCloud Keychain backup.
///
/// Tests and unsigned `swift test` invocations on a host without a user
/// passcode may need to relax the accessibility class; the `accessibility:`
/// init parameter is provided for that path. Production callers leave it
/// at the default.
///
/// Access group: when `accessGroup` is non-nil the store passes
/// `kSecAttrAccessGroup` so all four Synapse binaries (life/work × iOS/mac)
/// signed with the matching `keychain-access-groups` entitlement read and
/// write the same items. `nil` keeps the legacy single-app behavior so
/// unsigned `swift test` runs that lack the entitlement still pass.
public struct KeychainStore: Sendable {

    public let service: String

    /// The `kSecAttrAccessible` class this instance will request when writing
    /// items. Per-instance (rather than static) so tests can opt into a more
    /// relaxed class without mutating global state; production callers should
    /// leave it at the default.
    public let accessibility: String

    /// Shared keychain group for the four Synapse binaries. Matches the
    /// `keychain-access-groups` entitlement listed in the four
    /// `*.entitlements` files (owned by another agent — we do not touch
    /// them, only reference the group by name here).
    public static let sharedAccessGroup: String = "tech.synapse.shared"

    /// Access group passed via `kSecAttrAccessGroup`. `nil` ⇒ the request
    /// is omitted so unsigned test hosts (which lack the entitlement) do
    /// not get rejected with `errSecMissingEntitlement`.
    public let accessGroup: String?

    /// Default accessibility class for production callers. Strictly stronger
    /// than the previous default — items written under this class are
    /// unavailable on a device with no user passcode, and are excluded from
    /// iCloud Keychain backup.
    public static let defaultAccessibility: String =
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String

    /// Back-compat shim: the prior public surface exposed
    /// `KeychainStore.accessibilityClass` as a static let. Kept as an alias of
    /// `defaultAccessibility` so older call sites don't break, but new code
    /// should read it from the instance.
    public static var accessibilityClass: String { defaultAccessibility }

    public init(
        service: String,
        accessibility: String = KeychainStore.defaultAccessibility,
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessibility = accessibility
        self.accessGroup = accessGroup
    }

    /// Opting into the data-protection keychain (`kSecUseDataProtectionKeychain`)
    /// is the right answer on iOS and on signed macOS apps with the
    /// `keychain-access-groups` entitlement. In `swift test` against this
    /// package we are unsigned, so requesting it returns `-34018`
    /// (`errSecMissingEntitlement`). We therefore use the platform-default
    /// keychain here; the shipping app target sets this opt-in at build time
    /// once entitlements are present.
    private func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let group = accessGroup {
            q[kSecAttrAccessGroup as String] = group
        }
        return q
    }

    public func set(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailure }
        let query = baseQuery(account: account)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: self.accessibility
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query
            for (k, v) in attrs { add[k] = v }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func get(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
                throw KeychainError.encodingFailure
            }
            return s
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Delete is a no-op when the item is absent. We intentionally swallow
    /// `errSecItemNotFound` because deleting an already-absent key is not a
    /// failure from the caller's perspective.
    public func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Returns the raw `kSecAttrAccessible` value the item was stored with as
    /// a `String` for easy comparison. Tests can compare against
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String`.
    public func accessibility(account: String) throws -> String? {
        return try attributes(account: account)?[kSecAttrAccessible as String] as? String
    }

    /// Returns the full attribute dictionary for the stored item. Exposed so
    /// tests can inspect any attribute, not just accessibility.
    public func attributes(account: String) throws -> [String: Any]? {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? [String: Any]
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
