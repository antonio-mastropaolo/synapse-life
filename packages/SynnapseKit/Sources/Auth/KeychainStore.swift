import Foundation
import Security

public enum KeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case encodingFailure
}

/// Minimal Keychain wrapper around `SecItem*` for refresh-token storage and
/// other small secrets. Items are scoped by `service` and `account`, written
/// with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so they survive
/// reboots but cannot leak via iCloud Keychain backup.
public struct KeychainStore: Sendable {

    public let service: String

    /// The `kSecAttrAccessible` class this store will request when writing
    /// items. Surfaced so tests and code review can assert on it without
    /// round-tripping through the keychain (the legacy macOS keychain does
    /// not return the attribute on lookup).
    public static let accessibilityClass: String =
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    public init(service: String) {
        self.service = service
    }

    /// Opting into the data-protection keychain (`kSecUseDataProtectionKeychain`)
    /// is the right answer on iOS and on signed macOS apps with the
    /// `keychain-access-groups` entitlement. In `swift test` against this
    /// package we are unsigned, so requesting it returns `-34018`
    /// (`errSecMissingEntitlement`). We therefore use the platform-default
    /// keychain here; the shipping app target sets this opt-in at build time
    /// once entitlements are present.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func set(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailure }
        let query = baseQuery(account: account)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibilityClass
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
