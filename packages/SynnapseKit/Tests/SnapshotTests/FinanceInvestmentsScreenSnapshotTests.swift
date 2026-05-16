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

/// 4 references: macOS+iOS, light+dark.
@Suite("FinanceInvestmentsScreenSnapshot")
@MainActor
struct FinanceInvestmentsScreenSnapshotTests {

    private func vm() -> FinanceInvestmentsViewModel {
        let api = MockFinanceAPI()
        let vm = FinanceInvestmentsViewModel(api: api)
        let positions: [InvestmentPosition] = [
            InvestmentPosition(
                securityId: "voo", accountId: "brk", accountName: "Brokerage",
                ticker: "VOO", name: "Vanguard S&P 500 ETF", kind: .etf,
                quantity: Decimal(120), price: Decimal(string: "510.42")!,
                value: Decimal(string: "61250.40")!,
                costBasis: Decimal(string: "48000.00")!,
                unrealizedPnL: Decimal(string: "13250.40")!,
                unrealizedPnLPct: Decimal(string: "0.2760")!,
                currency: "USD"
            ),
            InvestmentPosition(
                securityId: "aapl", accountId: "brk", accountName: "Brokerage",
                ticker: "AAPL", name: "Apple Inc.", kind: .stock,
                quantity: Decimal(80), price: Decimal(string: "232.00")!,
                value: Decimal(string: "18560.00")!,
                costBasis: Decimal(string: "20000.00")!,
                unrealizedPnL: Decimal(string: "-1440.00")!,
                unrealizedPnLPct: Decimal(string: "-0.0720")!,
                currency: "USD"
            ),
            InvestmentPosition(
                securityId: "agg", accountId: "ira", accountName: "Rollover IRA",
                ticker: "AGG", name: "iShares Core U.S. Aggregate Bond ETF", kind: .bond,
                quantity: Decimal(200), price: Decimal(string: "98.50")!,
                value: Decimal(string: "19700.00")!,
                costBasis: Decimal(string: "20500.00")!,
                unrealizedPnL: Decimal(string: "-800.00")!,
                unrealizedPnLPct: Decimal(string: "-0.0390")!,
                currency: "USD"
            )
        ]
        vm.injectForSnapshots(positions: positions)
        return vm
    }

    #if os(macOS)
    private func hostMac(scheme: ColorScheme) -> NSView {
        let view = FinanceInvestmentsView(viewModel: vm())
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }
    @Test func lightMac() throws {
        assertSnapshot(of: hostMac(scheme: .light), as: .image, named: "finance.investments.light.mac")
    }
    @Test func darkMac() throws {
        assertSnapshot(of: hostMac(scheme: .dark), as: .image, named: "finance.investments.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(scheme: ColorScheme) -> UIViewController {
        let view = FinanceInvestmentsView(viewModel: vm())
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
                       named: "finance.investments.light.ios")
    }
    @Test func darkIOS() throws {
        assertSnapshot(of: hostIOS(scheme: .dark), as: .image(on: .iPhone13Pro),
                       named: "finance.investments.dark.ios")
    }
    #endif
}
