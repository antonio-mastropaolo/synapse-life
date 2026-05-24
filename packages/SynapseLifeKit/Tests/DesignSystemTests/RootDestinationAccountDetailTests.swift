import Foundation
import Testing
@testable import DesignSystem

/// Locks the `.accountDetail(id:)` destination contract — the
/// parameterized leaf reached from a MY ACCOUNTS sidebar row tap.
///
/// Companion to [[SidebarSelectionTests]] (which locks the legacy
/// `select(account:)` id-only slot) and [[RootShellSelectionTests]]
/// (which locks the pre-redesign finance routes). This file is the
/// canonical contract for the new convenience that drives the
/// in-depth `AccountDetailView` from the macOS sidebar AND from the
/// iOS Accounts-list push.
///
/// The case is intentionally absent from `canonicalOrder`: it never
/// renders as a sidebar row of its own (the account rows themselves
/// are the entry point), and `canonicalOrder` exists so other agents
/// can iterate the sidebar set without filtering parameterized
/// leaves manually. Mirrors `.ask` / `.anomalyExplainer`.
@Suite("RootDestination — .accountDetail(id:)")
@MainActor
struct RootDestinationAccountDetailTests {

    // MARK: - Equality on associated id

    @Test("Two .accountDetail values with the same id are equal")
    func equalWhenIdMatches() {
        #expect(RootDestination.accountDetail(id: "acc-credit-01")
                == RootDestination.accountDetail(id: "acc-credit-01"))
    }

    @Test("Two .accountDetail values with different ids are not equal")
    func notEqualWhenIdDiffers() {
        #expect(RootDestination.accountDetail(id: "acc-credit-01")
                != RootDestination.accountDetail(id: "acc-checking-01"))
    }

    @Test(".accountDetail does not collide with any top-level destination")
    func neverEqualsTopLevel() {
        for top in RootDestination.canonicalOrder {
            #expect(RootDestination.accountDetail(id: "x") != top,
                    ".accountDetail(id:) should never equal \(top)")
        }
    }

    // MARK: - Canonical order

    @Test(".accountDetail(id:) is NOT in canonicalOrder")
    func notInCanonicalOrder() {
        // It's parameterized — same rationale as `.ask` and
        // `.anomalyExplainer`. A sidebar iteration over
        // canonicalOrder must never paint an `.accountDetail` row.
        for top in RootDestination.canonicalOrder {
            if case .accountDetail = top {
                Issue.record(".accountDetail leaked into canonicalOrder")
            }
        }
    }

    @Test(".accountDetail(id:) is NOT in intelligenceOrder")
    func notInIntelligenceOrder() {
        for top in RootDestination.intelligenceOrder {
            if case .accountDetail = top {
                Issue.record(".accountDetail leaked into intelligenceOrder")
            }
        }
    }

    // MARK: - select(accountDetail:) sets both slots

    @Test("select(accountDetail:) sets both selection and selectedAccountId")
    func selectAccountDetailSetsBothSlots() {
        let vm = RootShellViewModel()
        vm.select(accountDetail: "acc-credit-01")
        #expect(vm.selection == .accountDetail(id: "acc-credit-01"))
        #expect(vm.selectedAccountId == "acc-credit-01")
    }

    @Test("select(accountDetail:) overrides an earlier top-level selection")
    func overridesPriorTopLevel() {
        let vm = RootShellViewModel()
        vm.select(.dashboard)
        vm.select(accountDetail: "acc-savings-01")
        #expect(vm.selection == .accountDetail(id: "acc-savings-01"))
        #expect(vm.selectedAccountId == "acc-savings-01")
        // Dashboard is no longer active — the parameterized leaf is.
        #expect(!vm.isActive(.dashboard))
        #expect(vm.isActive(.accountDetail(id: "acc-savings-01")))
    }

    @Test("Switching between two accounts updates both slots")
    func switchingBetweenAccounts() {
        let vm = RootShellViewModel()
        vm.select(accountDetail: "acc-a")
        #expect(vm.selectedAccountId == "acc-a")

        vm.select(accountDetail: "acc-b")
        #expect(vm.selection == .accountDetail(id: "acc-b"))
        #expect(vm.selectedAccountId == "acc-b")
    }

    // MARK: - Top-level taps clear the pinned account

    @Test("Top-level select(_:) clears the pinned account id")
    func topLevelClearsPinnedAccount() {
        let vm = RootShellViewModel()
        vm.select(accountDetail: "acc-credit-01")
        #expect(vm.selectedAccountId == "acc-credit-01")

        vm.select(.transactions)
        #expect(vm.selection == .transactions)
        #expect(vm.selectedAccountId == nil,
                "Top-level row tap must clear the drill-down id")
    }

    // MARK: - Coexistence with the legacy select(account:) slot

    @Test("Legacy select(account:) does NOT change selection")
    func legacySelectAccountKeepsDestination() {
        // The pre-redesign behavior — relied on by SidebarSelectionTests.
        // We keep it because removing it would break that contract.
        let vm = RootShellViewModel()
        vm.select(.dashboard)
        vm.select(account: "discover-it")
        #expect(vm.selectedAccountId == "discover-it")
        #expect(vm.selection == .dashboard,
                "select(account:) is id-only; selection must not flip")
    }
}
