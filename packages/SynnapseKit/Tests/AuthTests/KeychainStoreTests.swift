import Foundation
import Security
import Testing
@testable import Auth

/// On the iOS Simulator the data-protection keychain refuses `SecItem*` from
/// XCTest because the test runner is not signed with the host app's
/// `keychain-access-groups` entitlement (`errSecMissingEntitlement` / -34018).
/// On macOS (unsigned `swift test`) the legacy keychain accepts the call. We
/// therefore gate the round-trip tests so they only run where the keychain
/// actually answers; iOS device runs and macOS test runs both qualify.
#if targetEnvironment(simulator) && os(iOS)
private let keychainAvailable = false
#else
private let keychainAvailable = true
#endif

@Suite("KeychainStore")
struct KeychainStoreTests {

    private func uniqueService() -> String {
        "tech.synnapse.keychain.tests.\(UUID().uuidString)"
    }

    @Test(.enabled(if: keychainAvailable))
    func roundTripsValue() throws {
        let store = KeychainStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("token-abc", account: account)
        let read = try store.get(account: account)
        #expect(read == "token-abc")
    }

    @Test(.enabled(if: keychainAvailable))
    func overwritesExistingValue() throws {
        let store = KeychainStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("first", account: account)
        try store.set("second", account: account)
        let read = try store.get(account: account)
        #expect(read == "second")
    }

    @Test(.enabled(if: keychainAvailable))
    func deleteIsNoOpWhenAbsent() throws {
        let store = KeychainStore(service: uniqueService())
        // Must not throw.
        try store.delete(account: "never-written")
    }

    @Test
    func usesAfterFirstUnlockThisDeviceOnly() throws {
        // The legacy macOS keychain does not surface kSecAttrAccessible on
        // lookup. We instead pin the requested accessibility class on the
        // type so a regression in the write path is loud.
        let expected = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        #expect(KeychainStore.accessibilityClass == expected)
    }

    #if os(iOS)
    @Test(.enabled(if: keychainAvailable))
    func roundTripsAccessibilityAttributeOnIOS() throws {
        let store = KeychainStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("x", account: account)
        let access = try store.accessibility(account: account)
        #expect(access == KeychainStore.accessibilityClass)
    }
    #endif
}
