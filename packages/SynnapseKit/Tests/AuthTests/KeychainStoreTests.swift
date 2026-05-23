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

    /// Production callers leave `accessibility:` at the default
    /// (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`). For round-trip
    /// tests we explicitly relax to `…AfterFirstUnlockThisDeviceOnly` so the
    /// suite does not depend on the host having a login password set — the
    /// strict class is asserted separately in `defaultsToWhenPasscodeSet`.
    private func testStore(service: String) -> KeychainStore {
        KeychainStore(
            service: service,
            accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    @Test(.enabled(if: keychainAvailable))
    func roundTripsValue() throws {
        let store = testStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("token-abc", account: account)
        let read = try store.get(account: account)
        #expect(read == "token-abc")
    }

    @Test(.enabled(if: keychainAvailable))
    func overwritesExistingValue() throws {
        let store = testStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("first", account: account)
        try store.set("second", account: account)
        let read = try store.get(account: account)
        #expect(read == "second")
    }

    @Test(.enabled(if: keychainAvailable))
    func deleteIsNoOpWhenAbsent() throws {
        let store = testStore(service: uniqueService())
        // Must not throw.
        try store.delete(account: "never-written")
    }

    @Test
    func defaultsToWhenPasscodeSet() throws {
        // Production default tightened from `AfterFirstUnlockThisDeviceOnly`
        // to `WhenPasscodeSetThisDeviceOnly` so secrets cannot be hosted on
        // a device with no user passcode and cannot leak via iCloud Keychain
        // backup. The legacy macOS keychain does not surface the attribute
        // on lookup, so we pin the requested class on the type instead.
        let expected = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String
        #expect(KeychainStore.defaultAccessibility == expected)
        #expect(KeychainStore.accessibilityClass == expected) // back-compat alias

        // Instance accessibility defaults to the strong class…
        let defaultStore = KeychainStore(service: "x")
        #expect(defaultStore.accessibility == expected)
        // …but tests may opt into the relaxed class via the init parameter.
        let relaxed = KeychainStore(
            service: "x",
            accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        #expect(relaxed.accessibility == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    #if os(iOS)
    @Test(.enabled(if: keychainAvailable))
    func roundTripsAccessibilityAttributeOnIOS() throws {
        let store = testStore(service: uniqueService())
        let account = "refresh-token"
        defer { try? store.delete(account: account) }

        try store.set("x", account: account)
        let access = try store.accessibility(account: account)
        // The test store was constructed with the relaxed class; assert the
        // attribute round-trips that class, not the static default.
        #expect(access == store.accessibility)
    }
    #endif
}
