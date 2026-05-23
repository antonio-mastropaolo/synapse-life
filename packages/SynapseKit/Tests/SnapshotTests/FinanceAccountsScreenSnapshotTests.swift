import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Models
@testable import Networking
@testable import Features
@testable import DesignSystem

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 4 references: macOS+iOS, light+dark, one populated state.
@Suite("FinanceAccountsScreenSnapshot")
@MainActor
struct FinanceAccountsScreenSnapshotTests {

    private func vm() -> FinanceAccountsViewModel {
        let api = MockFinanceAPI()
        let vm = FinanceAccountsViewModel(api: api)
        let accounts: [FinanceAccount] = [
            FinanceAccount(
                id: "cash", institutionId: "ins_chase", institutionName: "Chase",
                name: "Total Checking", officialName: nil, mask: "1234",
                kind: .checking, currency: "USD",
                currentBalance: Decimal(string: "12345.67"),
                availableBalance: nil, limitAmount: nil, balanceCapturedAt: nil
            ),
            FinanceAccount(
                id: "save", institutionId: "ins_chase", institutionName: "Chase",
                name: "Savings", officialName: nil, mask: "5678",
                kind: .savings, currency: "USD",
                currentBalance: Decimal(string: "44000.00"),
                availableBalance: nil, limitAmount: nil, balanceCapturedAt: nil
            ),
            FinanceAccount(
                id: "brk", institutionId: "ins_fidelity", institutionName: "Fidelity",
                name: "Brokerage", officialName: nil, mask: "0042",
                kind: .brokerage, currency: "USD",
                currentBalance: Decimal(string: "182450.00"),
                availableBalance: nil, limitAmount: nil, balanceCapturedAt: nil
            ),
            FinanceAccount(
                id: "cc", institutionId: "ins_chase", institutionName: "Chase",
                name: "Sapphire Preferred", officialName: nil, mask: "0001",
                kind: .credit, currency: "USD",
                currentBalance: Decimal(string: "2410.99"),
                availableBalance: nil, limitAmount: Decimal(20_000), balanceCapturedAt: nil
            )
        ]
        vm.injectForSnapshots(accounts: accounts)
        return vm
    }

    #if os(macOS)
    private func hostMac(scheme: ColorScheme) -> NSView {
        let view = FinanceAccountsView(viewModel: vm())
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }
    @Test func lightMac() throws {
        assertSnapshot(of: hostMac(scheme: .light), as: .image, named: "finance.accounts.light.mac")
    }
    @Test func darkMac() throws {
        assertSnapshot(of: hostMac(scheme: .dark), as: .image, named: "finance.accounts.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(scheme: ColorScheme) -> UIViewController {
        let view = FinanceAccountsView(viewModel: vm())
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }
    @Test func lightIOS() throws {
        assertSnapshot(of: hostIOS(scheme: .light), as: .image(on: .iPhone13Pro),
                       named: "finance.accounts.light.ios")
    }
    @Test func darkIOS() throws {
        assertSnapshot(of: hostIOS(scheme: .dark), as: .image(on: .iPhone13Pro),
                       named: "finance.accounts.dark.ios")
    }
    #endif
}
