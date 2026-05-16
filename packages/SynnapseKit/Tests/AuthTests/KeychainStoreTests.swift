import Foundation
import Security
import Testing
@testable import Auth

@Suite("KeychainStore")
struct KeychainStoreTests {

    private func uniqueService() -> String {
        "tech.synnapse.keychain.tests.\(UUID().uuidString)"
    }

    @Test
    func roundTripsValue() throws {
        let store = KeychainStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("token-abc", account: account)
        let read = try store.get(account: account)
        #expect(read == "token-abc")
    }

    @Test
    func overwritesExistingValue() throws {
        let store = KeychainStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("first", account: account)
        try store.set("second", account: account)
        let read = try store.get(account: account)
        #expect(read == "second")
    }

    @Test
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
    @Test
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
