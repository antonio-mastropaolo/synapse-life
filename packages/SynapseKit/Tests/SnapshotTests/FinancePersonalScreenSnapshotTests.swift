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

/// 12 references: macOS+iOS, light+dark, three states
/// (loading, ready, ready+concealBalances). See memory
/// `feedback_snapshot_macos` — macOS wraps the view in NSHostingView.
@Suite("FinancePersonalScreenSnapshot")
@MainActor
struct FinancePersonalScreenSnapshotTests {

    private func sampleAccounts() -> [FinanceAccount] {
        [
            FinanceAccount(
                id: "cash", institutionId: "ins_chase", institutionName: "Chase",
                name: "Total Checking", officialName: "Chase Total Checking", mask: "1234",
                kind: .checking, currency: "USD",
                currentBalance: Decimal(string: "12345.67"),
                availableBalance: Decimal(string: "12000.00"),
                limitAmount: nil, balanceCapturedAt: Date(timeIntervalSince1970: 1_739_625_600)
            ),
            FinanceAccount(
                id: "save", institutionId: "ins_chase", institutionName: "Chase",
                name: "Savings", officialName: "Chase Savings", mask: "5678",
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
    }

    private func readyVM(concealed: Bool) -> FinancePersonalViewModel {
        let api = MockFinanceAPI()
        let vm = FinancePersonalViewModel(api: api)
        vm.injectForSnapshots(state: .ready(.init(
            accounts: sampleAccounts(),
            netWorth: Decimal(string: "236385.68"),
            allocation: (try? PortfolioReducer.allocation(sampleAccounts())) ?? []
        )))
        if concealed {
            vm.scenePhaseDidChange(.inactive)
        }
        return vm
    }

    private func loadingVM() -> FinancePersonalViewModel {
        let api = MockFinanceAPI()
        let vm = FinancePersonalViewModel(api: api)
        vm.injectForSnapshots(state: .loading)
        return vm
    }

    #if os(macOS)
    private func hostMac(_ vm: FinancePersonalViewModel, scheme: ColorScheme) -> NSView {
        let view = FinancePersonalView(viewModel: vm)
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func loadingLightMac() throws {
        assertSnapshot(of: hostMac(loadingVM(), scheme: .light), as: .image,
                       named: "finance.personal.loading.light.mac")
    }
    @Test func loadingDarkMac() throws {
        assertSnapshot(of: hostMac(loadingVM(), scheme: .dark), as: .image,
                       named: "finance.personal.loading.dark.mac")
    }
    @Test func readyLightMac() throws {
        assertSnapshot(of: hostMac(readyVM(concealed: false), scheme: .light), as: .image,
                       named: "finance.personal.ready.light.mac")
    }
    @Test func readyDarkMac() throws {
        assertSnapshot(of: hostMac(readyVM(concealed: false), scheme: .dark), as: .image,
                       named: "finance.personal.ready.dark.mac")
    }
    @Test func concealedLightMac() throws {
        assertSnapshot(of: hostMac(readyVM(concealed: true), scheme: .light), as: .image,
                       named: "finance.personal.concealed.light.mac")
    }
    @Test func concealedDarkMac() throws {
        assertSnapshot(of: hostMac(readyVM(concealed: true), scheme: .dark), as: .image,
                       named: "finance.personal.concealed.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ vm: FinancePersonalViewModel, scheme: ColorScheme) -> UIViewController {
        let view = FinancePersonalView(viewModel: vm)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func loadingLightIOS() throws {
        assertSnapshot(of: hostIOS(loadingVM(), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "finance.personal.loading.light.ios")
    }
    @Test func loadingDarkIOS() throws {
        assertSnapshot(of: hostIOS(loadingVM(), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "finance.personal.loading.dark.ios")
    }
    @Test func readyLightIOS() throws {
        assertSnapshot(of: hostIOS(readyVM(concealed: false), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "finance.personal.ready.light.ios")
    }
    @Test func readyDarkIOS() throws {
        assertSnapshot(of: hostIOS(readyVM(concealed: false), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "finance.personal.ready.dark.ios")
    }
    @Test func concealedLightIOS() throws {
        assertSnapshot(of: hostIOS(readyVM(concealed: true), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "finance.personal.concealed.light.ios")
    }
    @Test func concealedDarkIOS() throws {
        assertSnapshot(of: hostIOS(readyVM(concealed: true), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "finance.personal.concealed.dark.ios")
    }
    #endif
}
