import Foundation
import Testing
@testable import DesignSystem

/// Locks the Copilot-shaped sidebar destinations the macOS shell exposes
/// after the redesign.
///
/// The brief introduces ten new top-level sidebar rows — dashboard,
/// transactions, goals, cashFlow, accounts, investments, categories,
/// recurrings, subscriptions, plus the surviving life/advisors. This
/// suite is the contract the SwiftUI sidebar binds against: tapping a
/// row sets `selection` to the corresponding `RootDestination`, the
/// per-row `isActive(_:)` helper paints the accent bar, and the
/// `selectedAccountId` slot records a tap on a MY ACCOUNTS row without
/// disturbing the current destination (the actual Transactions filter
/// hook lands on agent 2).
///
/// Pairs with [[RootShellSelectionTests]] which still locks the
/// pre-existing finance-leaf / life / advisors paths. New destinations
/// are exercised here so a regression in the redesign cannot silently
/// erase a sidebar row.
@Suite("Sidebar selection — Copilot redesign")
@MainActor
struct SidebarSelectionTests {

    // MARK: - Top-level destination round-trip

    @Test("Default selection is Dashboard")
    func defaultIsDashboard() {
        let vm = RootShellViewModel()
        #expect(vm.selection == .dashboard)
        #expect(vm.isActive(.dashboard))
    }

    @Test("Each new top-level destination round-trips through select(_:)")
    func newDestinationsRoundTrip() {
        let destinations: [RootDestination] = [
            .dashboard,
            .transactions,
            .goals,
            .cashFlow,
            .accounts,
            .investments,
            .categories,
            .recurrings,
            .subscriptions,
            .life,
            .advisors
        ]

        for destination in destinations {
            let vm = RootShellViewModel()
            vm.select(destination)
            #expect(vm.selection == destination,
                    "Selection should be \(destination), was \(vm.selection)")
            #expect(vm.isActive(destination),
                    "isActive should be true for \(destination)")
        }
    }

    @Test("isActive only matches the selected destination")
    func isActiveIsExact() {
        let vm = RootShellViewModel()
        vm.select(.categories)
        for other in RootDestination.canonicalOrder where other != .categories {
            #expect(!vm.isActive(other),
                    "Only .categories should be active, not \(other)")
        }
    }

    // MARK: - Canonical order

    @Test("Canonical sidebar order matches the Copilot redesign")
    func canonicalOrder() {
        // The list below is the source of truth for the order rows are
        // painted in the macOS sidebar. Other agents render content for
        // these destinations and rely on this contract to know which
        // row is which. Changing the order is a breaking change.
        let expected: [RootDestination] = [
            .dashboard,
            .transactions,
            .goals,
            .cashFlow,
            .accounts,
            .investments,
            .categories,
            .recurrings,
            .subscriptions,
            .life,
            .advisors
        ]
        #expect(RootDestination.canonicalOrder == expected)
    }

    // MARK: - Account row taps

    @Test("Tapping a MY ACCOUNTS row records the account id without changing destination")
    func accountTapRecordsId() {
        let vm = RootShellViewModel()
        vm.select(.dashboard)
        #expect(vm.selectedAccountId == nil)

        vm.select(account: "discover-it")
        #expect(vm.selectedAccountId == "discover-it")
        // The destination is unchanged — the wiring that follows the
        // account id into Transactions is agent 2's hook.
        #expect(vm.selection == .dashboard)
    }

    @Test("Tapping a top-level row clears the selected account")
    func topLevelTapClearsAccount() {
        let vm = RootShellViewModel()
        vm.select(account: "paypal-credit")
        #expect(vm.selectedAccountId == "paypal-credit")

        vm.select(.goals)
        #expect(vm.selection == .goals)
        #expect(vm.selectedAccountId == nil,
                "Top-level selection should clear the pinned account")
    }

    // MARK: - Back-compat with the pre-redesign finance routes

    @Test("Legacy .finance(_) selections still survive")
    func legacyFinanceStillWorks() {
        // [[RootShellSelectionTests]] continues to lock the legacy
        // .finance(FinanceSurface) path. We just sanity-check that the
        // Copilot redesign did not delete the case.
        let vm = RootShellViewModel()
        vm.select(.finance(.transactions))
        #expect(vm.selection == .finance(.transactions))
        #expect(vm.isActiveFinanceSurface(.transactions))
    }
}
