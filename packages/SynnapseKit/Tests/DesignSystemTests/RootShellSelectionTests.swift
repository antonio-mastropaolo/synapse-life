import Foundation
import Testing
@testable import DesignSystem

/// Locks the macOS Cockpit shell sidebar interaction contract.
///
/// Before this test landed the sidebar in `RootView` was a static label
/// list — clicking a row was a no-op because the rows had no button
/// wrapper and the detail pane was deterministic preview content. The
/// fix introduces [[RootShellViewModel]] as the pure selection state the
/// SwiftUI sidebar binds against. This suite pins the state machine the
/// view consumes: tapping a row sets `selection`, the parent FINANCE
/// row activates for any finance leaf, and the exact-match helper used
/// by child rows distinguishes leaves.
@Suite("Root shell selection")
@MainActor
struct RootShellSelectionTests {

    @Test("Default selection is Dashboard (Copilot redesign)")
    func defaultSelectionIsDashboard() {
        // The pre-Copilot default was `.finance(.personal)`. The redesign
        // promotes Dashboard to the canonical landing surface to match
        // the reference shell — agent 2 owns the Dashboard view that
        // paints under this selection.
        let vm = RootShellViewModel()
        #expect(vm.selection == .dashboard)
    }

    @Test("Legacy finance default is reachable via explicit init")
    func legacyFinanceDefaultReachable() {
        // Callers that want the pre-redesign landing surface can pass
        // `.finance(.personal)` explicitly. The destination still exists
        // for the FinanceSubRouter path inside the live shell.
        let vm = RootShellViewModel(selection: .finance(.personal))
        #expect(vm.selection == .finance(.personal))
    }

    @Test("Selecting LIFE switches the destination")
    func selectingLifeSwitchesDestination() {
        let vm = RootShellViewModel()
        vm.select(.life)
        #expect(vm.selection == .life)
    }

    @Test("Selecting ADVISORS switches the destination")
    func selectingAdvisorsSwitchesDestination() {
        let vm = RootShellViewModel()
        vm.select(.advisors)
        #expect(vm.selection == .advisors)
    }

    @Test("Selecting a finance leaf updates the active surface")
    func selectingFinanceLeafUpdatesSurface() {
        let vm = RootShellViewModel()
        vm.select(.finance(.transactions))
        #expect(vm.selection == .finance(.transactions))
        #expect(vm.isActiveFinanceSurface(.transactions))
        #expect(!vm.isActiveFinanceSurface(.personal))
    }

    @Test("FINANCE parent row activates for every finance leaf")
    func financeParentActivatesForEveryLeaf() {
        let vm = RootShellViewModel()
        for surface in FinanceSurface.allCases {
            vm.select(.finance(surface))
            // `RootDestination.finance(.personal)` is the canonical encoding
            // of the FINANCE parent row in the sidebar — `isActive` treats
            // any `.finance(_)` selection as activating the parent row.
            #expect(vm.isActive(.finance(.personal)),
                    "FINANCE parent should activate for leaf \(surface)")
        }
    }

    @Test("LIFE/ADVISORS only activate for themselves")
    func lifeAdvisorsOnlyActivateForThemselves() {
        let vm = RootShellViewModel()
        vm.select(.life)
        #expect(vm.isActive(.life))
        #expect(!vm.isActive(.advisors))
        #expect(!vm.isActive(.finance(.personal)))

        vm.select(.advisors)
        #expect(vm.isActive(.advisors))
        #expect(!vm.isActive(.life))
        #expect(!vm.isActive(.finance(.personal)))
    }

    @Test("Child row activates only for its exact surface")
    func childRowActivatesOnlyForExactSurface() {
        let vm = RootShellViewModel()
        vm.select(.finance(.accounts))
        #expect(vm.isActiveFinanceSurface(.accounts))
        for other in FinanceSurface.allCases where other != .accounts {
            #expect(!vm.isActiveFinanceSurface(other),
                    "Only accounts should be active, not \(other)")
        }
    }
}
