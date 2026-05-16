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

/// 4 references = macOS desk × 2 schemes + iOS placeholder × 2 schemes.
@Suite("TradingDeskScreenSnapshot")
@MainActor
struct TradingDeskScreenSnapshotTests {

    private func samplePositions() -> [InvestmentPosition] {
        [
            InvestmentPosition(
                securityId: "sec_AAPL", accountId: "acc_brk", accountName: "Brokerage",
                ticker: "AAPL", name: "Apple Inc.",
                kind: .stock,
                quantity: Decimal(string: "180.50")!,
                price: Decimal(string: "182.40")!,
                value: Decimal(string: "32_923.20")!,
                costBasis: Decimal(string: "25_000.00")!,
                unrealizedPnL: Decimal(string: "7923.20")!,
                unrealizedPnLPct: Decimal(string: "31.69")!,
                currency: "USD"
            ),
            InvestmentPosition(
                securityId: "sec_MSFT", accountId: "acc_brk", accountName: "Brokerage",
                ticker: "MSFT", name: "Microsoft Corp.",
                kind: .stock,
                quantity: Decimal(string: "85.00")!,
                price: Decimal(string: "412.00")!,
                value: Decimal(string: "35_020.00")!,
                costBasis: Decimal(string: "28_000.00")!,
                unrealizedPnL: Decimal(string: "7020.00")!,
                unrealizedPnLPct: Decimal(string: "25.07")!,
                currency: "USD"
            ),
            InvestmentPosition(
                securityId: "sec_VTI", accountId: "acc_ira", accountName: "Roth IRA",
                ticker: "VTI", name: "Vanguard Total Stock Market ETF",
                kind: .etf,
                quantity: Decimal(string: "120.00")!,
                price: Decimal(string: "248.75")!,
                value: Decimal(string: "29_850.00")!,
                costBasis: Decimal(string: "27_500.00")!,
                unrealizedPnL: Decimal(string: "2350.00")!,
                unrealizedPnLPct: Decimal(string: "8.55")!,
                currency: "USD"
            ),
            InvestmentPosition(
                securityId: "sec_NVDA", accountId: "acc_brk", accountName: "Brokerage",
                ticker: "NVDA", name: "NVIDIA Corp.",
                kind: .stock,
                quantity: Decimal(string: "40.00")!,
                price: Decimal(string: "894.50")!,
                value: Decimal(string: "35_780.00")!,
                costBasis: Decimal(string: "18_000.00")!,
                unrealizedPnL: Decimal(string: "17_780.00")!,
                unrealizedPnLPct: Decimal(string: "98.78")!,
                currency: "USD"
            )
        ]
    }

    private func readyVM() -> TradingDeskViewModel {
        let api = MockFinanceAPI()
        let vm = TradingDeskViewModel(api: api)
        vm.injectForSnapshots(positions: samplePositions(), selectedSymbol: "NVDA")
        return vm
    }

    #if os(macOS)
    private func hostMac<Root: View>(_ root: Root, scheme: ColorScheme) -> NSView {
        let view = root
            .frame(width: 1280, height: 720)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func deskLightMac() throws {
        assertSnapshot(of: hostMac(TradingDeskView(viewModel: readyVM()), scheme: .light),
                       as: .image, named: "trading.desk.light.mac")
    }
    @Test func deskDarkMac() throws {
        assertSnapshot(of: hostMac(TradingDeskView(viewModel: readyVM()), scheme: .dark),
                       as: .image, named: "trading.desk.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS<Root: View>(_ root: Root, scheme: ColorScheme) -> UIViewController {
        let view = root
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func placeholderLightIOS() throws {
        assertSnapshot(of: hostIOS(TradingDeskPlaceholderView(), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "trading.desk.placeholder.light.ios")
    }
    @Test func placeholderDarkIOS() throws {
        assertSnapshot(of: hostIOS(TradingDeskPlaceholderView(), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "trading.desk.placeholder.dark.ios")
    }
    #endif
}
