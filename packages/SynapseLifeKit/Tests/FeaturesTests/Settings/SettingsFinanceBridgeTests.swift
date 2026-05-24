import Foundation
import SwiftUI
import Testing
@testable import Models
@testable import Networking
@testable import Features

/// Integration test: the M9 `SettingsViewModel.concealBalances` toggle must
/// stay observable by [[FinancePersonalViewModel]] from M5, so the app
/// shell can wire one to the other without leaking either type's internals.
///
/// The M5 view model exposes `concealBalances` as `public private(set)` and
/// flips it on scene-phase transitions to background. M9 reuses that signal
/// path: the settings toggle, when on, behaves as if the scene phase had
/// gone inactive. This test pins both halves of the contract.
@Suite("Settings ↔ FinancePersonal bridge")
@MainActor
struct SettingsFinanceBridgeTests {

    @Test
    func scenePhaseInactiveFlipsConcealOn() {
        let api = MockFinanceAPI()
        let finance = FinancePersonalViewModel(api: api)
        #expect(finance.concealBalances == false)
        finance.scenePhaseDidChange(.inactive)
        #expect(finance.concealBalances == true)
        finance.scenePhaseDidChange(.active)
        #expect(finance.concealBalances == false)
    }

    @Test
    func settingsToggleStaysInLockstepThroughTheStore() {
        let store = InMemorySettingsStore()
        let settings = SettingsViewModel(store: store)
        let api = MockFinanceAPI()
        let finance = FinancePersonalViewModel(api: api)

        // Operator turns on conceal-balances in Settings.
        settings.concealBalances = true
        #expect(store.read().concealBalances == true)

        // The app shell mirrors the preference into the finance VM by
        // forwarding a `.inactive`-equivalent signal whenever the
        // preference is on. The bridge below stands in for what
        // `AppModel` will do at the call site — M9 keeps this pure so the
        // contract is testable without spinning up the SwiftUI host.
        if settings.concealBalances {
            finance.scenePhaseDidChange(.inactive)
        } else {
            finance.scenePhaseDidChange(.active)
        }
        #expect(finance.concealBalances == true)

        // Flip back: the bridge surrenders control to scene phase again.
        settings.concealBalances = false
        if settings.concealBalances {
            finance.scenePhaseDidChange(.inactive)
        } else {
            finance.scenePhaseDidChange(.active)
        }
        #expect(finance.concealBalances == false)
    }
}
