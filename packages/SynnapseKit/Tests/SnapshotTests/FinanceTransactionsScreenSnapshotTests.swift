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

/// 8 references: macOS+iOS, light+dark, two states (populated, filtered).
@Suite("FinanceTransactionsScreenSnapshot")
@MainActor
struct FinanceTransactionsScreenSnapshotTests {

    private static let day0 = Date(timeIntervalSince1970: 1_734_652_800) // 2024-12-20

    private func sampleTransactions() -> [Models.Transaction] {
        [
            Models.Transaction(
                id: "t1", accountId: "cash", accountName: "Chase Checking",
                amount: Decimal(string: "-4.55"), currency: "USD",
                date: Self.day0,
                name: "BLUE BOTTLE COFFEE", merchantName: "Blue Bottle",
                category: .knownCategory("Food & Drink"), subcategory: nil, pending: false
            ),
            Models.Transaction(
                id: "t2", accountId: "cash", accountName: "Chase Checking",
                amount: Decimal(string: "-89.00"), currency: "USD",
                date: Self.day0.addingTimeInterval(86_400),
                name: "FRESH MARKET", merchantName: "The Fresh Market",
                category: .knownCategory("Groceries"), subcategory: nil, pending: false
            ),
            Models.Transaction(
                id: "t3", accountId: "cc", accountName: "Sapphire",
                amount: Decimal(string: "-22.10"), currency: "USD",
                date: Self.day0.addingTimeInterval(2 * 86_400),
                name: "UBER TRIP", merchantName: "Uber",
                category: .knownCategory("Transportation"), subcategory: "Ride Share", pending: true
            ),
            Models.Transaction(
                id: "t4", accountId: "cash", accountName: "Chase Checking",
                amount: Decimal(2_400), currency: "USD",
                date: Self.day0.addingTimeInterval(3 * 86_400),
                name: "PAYROLL DEPOSIT", merchantName: nil,
                category: .knownCategory("Income"), subcategory: nil, pending: false
            )
        ]
    }

    private func sampleAccounts() -> [Models.FinanceAccount] {
        [
            Models.FinanceAccount(
                id: "cash", institutionId: nil, institutionName: "Bank of America",
                name: "Adv Plus Banking", officialName: nil, mask: "4223",
                kind: .checking, currency: "USD",
                currentBalance: nil, availableBalance: nil,
                limitAmount: nil, balanceCapturedAt: nil
            ),
            Models.FinanceAccount(
                id: "cc", institutionId: nil, institutionName: "Chase",
                name: "Sapphire Reserve", officialName: nil, mask: "0001",
                kind: .credit, currency: "USD",
                currentBalance: nil, availableBalance: nil,
                limitAmount: nil, balanceCapturedAt: nil
            )
        ]
    }

    private func populatedVM() -> FinanceTransactionsViewModel {
        let api = MockFinanceAPI()
        let vm = FinanceTransactionsViewModel(api: api, accountId: nil)
        vm.injectForSnapshots(
            transactions: sampleTransactions(),
            accounts: sampleAccounts(),
            filter: LedgerFilter()
        )
        return vm
    }

    private func filteredVM() -> FinanceTransactionsViewModel {
        let api = MockFinanceAPI()
        let vm = FinanceTransactionsViewModel(api: api, accountId: nil)
        var filter = LedgerFilter()
        filter.categories = ["Food & Drink"]
        vm.injectForSnapshots(
            transactions: sampleTransactions(),
            accounts: sampleAccounts(),
            filter: filter
        )
        return vm
    }

    #if os(macOS)
    private func hostMac(_ vm: FinanceTransactionsViewModel, scheme: ColorScheme) -> NSView {
        let view = FinanceTransactionsView(viewModel: vm)
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }
    @Test func populatedLightMac() throws {
        assertSnapshot(of: hostMac(populatedVM(), scheme: .light), as: .image,
                       named: "finance.transactions.populated.light.mac")
    }
    @Test func populatedDarkMac() throws {
        assertSnapshot(of: hostMac(populatedVM(), scheme: .dark), as: .image,
                       named: "finance.transactions.populated.dark.mac")
    }
    @Test func filteredLightMac() throws {
        assertSnapshot(of: hostMac(filteredVM(), scheme: .light), as: .image,
                       named: "finance.transactions.filtered.light.mac")
    }
    @Test func filteredDarkMac() throws {
        assertSnapshot(of: hostMac(filteredVM(), scheme: .dark), as: .image,
                       named: "finance.transactions.filtered.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ vm: FinanceTransactionsViewModel, scheme: ColorScheme) -> UIViewController {
        let view = FinanceTransactionsView(viewModel: vm)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }
    @Test func populatedLightIOS() throws {
        assertSnapshot(of: hostIOS(populatedVM(), scheme: .light), as: .image(on: .iPhone13Pro),
                       named: "finance.transactions.populated.light.ios")
    }
    @Test func populatedDarkIOS() throws {
        assertSnapshot(of: hostIOS(populatedVM(), scheme: .dark), as: .image(on: .iPhone13Pro),
                       named: "finance.transactions.populated.dark.ios")
    }
    @Test func filteredLightIOS() throws {
        assertSnapshot(of: hostIOS(filteredVM(), scheme: .light), as: .image(on: .iPhone13Pro),
                       named: "finance.transactions.filtered.light.ios")
    }
    @Test func filteredDarkIOS() throws {
        assertSnapshot(of: hostIOS(filteredVM(), scheme: .dark), as: .image(on: .iPhone13Pro),
                       named: "finance.transactions.filtered.dark.ios")
    }
    #endif
}
