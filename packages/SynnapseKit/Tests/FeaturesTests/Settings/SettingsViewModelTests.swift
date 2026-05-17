import Foundation
import Testing
@testable import Features

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {

    @Test
    func defaultsAreReadOnInit() {
        let store = InMemorySettingsStore(initial: SettingsSnapshot(
            apiBaseURL: "https://example.test",
            concealBalances: true,
            reduceMotionPreview: false
        ))
        let vm = SettingsViewModel(store: store)
        #expect(vm.apiBaseURL == "https://example.test")
        #expect(vm.concealBalances)
        #expect(vm.reduceMotionPreview == false)
    }

    @Test
    func mutationsPersistBack() {
        let store = InMemorySettingsStore()
        let vm = SettingsViewModel(store: store)
        vm.apiBaseURL = "https://api.example.test"
        vm.concealBalances = true
        let persisted = store.read()
        #expect(persisted.apiBaseURL == "https://api.example.test")
        #expect(persisted.concealBalances)
    }

    @Test
    func apiBaseURLValidation() {
        let store = InMemorySettingsStore()
        let vm = SettingsViewModel(store: store)
        vm.apiBaseURL = ""
        #expect(vm.apiBaseURLIsValid)
        vm.apiBaseURL = "https://example.test"
        #expect(vm.apiBaseURLIsValid)
        vm.apiBaseURL = "not a url"
        #expect(vm.apiBaseURLIsValid == false)
        vm.apiBaseURL = "ftp://example.test"
        #expect(vm.apiBaseURLIsValid == false)
    }

    @Test
    func resetToDefaultsRoundtripsThroughStore() {
        let store = InMemorySettingsStore(initial: SettingsSnapshot(
            apiBaseURL: "https://x",
            concealBalances: true,
            reduceMotionPreview: true
        ))
        let vm = SettingsViewModel(store: store)
        vm.resetToDefaults()
        let snap = store.read()
        #expect(snap.apiBaseURL == "")
        #expect(snap.concealBalances == false)
        #expect(snap.reduceMotionPreview == false)
    }

    @Test
    func userDefaultsStoreRoundTrips() {
        let suiteName = "synnapse.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let snap = SettingsSnapshot(
            apiBaseURL: "https://round.trip",
            concealBalances: true,
            reduceMotionPreview: true
        )
        store.write(snap)
        let read = store.read()
        #expect(read == snap)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
