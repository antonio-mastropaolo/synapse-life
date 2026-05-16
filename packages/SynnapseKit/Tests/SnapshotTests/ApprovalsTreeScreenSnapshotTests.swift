import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Models
@testable import Features
@testable import DesignSystem

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Snapshot references for `ApprovalsTreeView`. 12 total — 3 states
/// (collapsed, partially-expanded, fully-expanded) × 2 schemes × 2 platforms.
@Suite("ApprovalsTreeScreenSnapshot")
@MainActor
struct ApprovalsTreeScreenSnapshotTests {

    private func sampleBundle() -> ApprovalsBundle {
        let approvals = [
            Approval(
                id: "ap-anthropic",
                title: "Re: Anthropic API spend (Q1 2026)",
                vendor: "Anthropic",
                approver: "Jacqulyn Ledger",
                approverRole: "admin-coordinator",
                category: "ai-tools",
                requestedAt: Date(timeIntervalSince1970: 1_739_625_600),
                validUntil: nil,
                status: .approved,
                workdayURL: URL(string: "https://wd5.myworkday.com/wm/d/inst/1/expense"),
                totalAmount: Decimal(string: "412.55"),
                currency: "USD"
            ),
            Approval(
                id: "ap-openai",
                title: "Re: OpenAI API spend",
                vendor: "OpenAI",
                approver: "Jacqulyn Ledger",
                approverRole: "admin-coordinator",
                category: "ai-tools",
                requestedAt: Date(timeIntervalSince1970: 1_730_000_000),
                validUntil: nil,
                status: .pending,
                workdayURL: nil,
                totalAmount: Decimal(string: "187.20"),
                currency: "USD"
            )
        ]
        let receipts = [
            Receipt(id: "r-a-1", approvalId: "ap-anthropic", vendor: "Anthropic",
                    amount: Decimal(string: "200.00"), currency: "USD",
                    date: "2026-02-10", documentKind: .receipt,
                    sourceAccount: "amastropaolo@wm.edu", submissionStatus: "pending"),
            Receipt(id: "r-a-2", approvalId: "ap-anthropic", vendor: "Anthropic",
                    amount: Decimal(string: "212.55"), currency: "USD",
                    date: "2026-03-12", documentKind: .receipt,
                    sourceAccount: "amastropaolo@wm.edu", submissionStatus: "pending"),
            Receipt(id: "r-o-1", approvalId: "ap-openai", vendor: "OpenAI",
                    amount: Decimal(string: "187.20"), currency: "USD",
                    date: "2026-02-22", documentKind: .receipt,
                    sourceAccount: "amastropaolo@wm.edu", submissionStatus: "pending")
        ]
        return ApprovalsBundle(approvals: approvals, receipts: receipts)
    }

    private enum Expansion { case collapsed, partial, full }

    private func viewModel(_ expansion: Expansion) -> ApprovalsTreeViewModel {
        let mock = MockApprovalsAPI()
        let vm = ApprovalsTreeViewModel(api: mock)
        vm.injectForSnapshots(bundle: sampleBundle())
        switch expansion {
        case .collapsed:
            vm.collapseAll()
        case .partial:
            vm.injectExpanded(["ap-anthropic"])
        case .full:
            vm.expandAll()
        }
        return vm
    }

    #if os(macOS)
    private func hostMac(_ vm: ApprovalsTreeViewModel, scheme: ColorScheme) -> NSView {
        let view = ApprovalsTreeView(viewModel: vm)
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func collapsedLightMac() throws {
        assertSnapshot(of: hostMac(viewModel(.collapsed), scheme: .light), as: .image,
                       named: "approvals.tree.collapsed.light.mac")
    }
    @Test func collapsedDarkMac() throws {
        assertSnapshot(of: hostMac(viewModel(.collapsed), scheme: .dark), as: .image,
                       named: "approvals.tree.collapsed.dark.mac")
    }
    @Test func partialLightMac() throws {
        assertSnapshot(of: hostMac(viewModel(.partial), scheme: .light), as: .image,
                       named: "approvals.tree.partial.light.mac")
    }
    @Test func partialDarkMac() throws {
        assertSnapshot(of: hostMac(viewModel(.partial), scheme: .dark), as: .image,
                       named: "approvals.tree.partial.dark.mac")
    }
    @Test func fullLightMac() throws {
        assertSnapshot(of: hostMac(viewModel(.full), scheme: .light), as: .image,
                       named: "approvals.tree.full.light.mac")
    }
    @Test func fullDarkMac() throws {
        assertSnapshot(of: hostMac(viewModel(.full), scheme: .dark), as: .image,
                       named: "approvals.tree.full.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ vm: ApprovalsTreeViewModel, scheme: ColorScheme) -> UIViewController {
        let view = ApprovalsTreeView(viewModel: vm)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func collapsedLightIOS() throws {
        assertSnapshot(of: hostIOS(viewModel(.collapsed), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "approvals.tree.collapsed.light.ios")
    }
    @Test func collapsedDarkIOS() throws {
        assertSnapshot(of: hostIOS(viewModel(.collapsed), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "approvals.tree.collapsed.dark.ios")
    }
    @Test func partialLightIOS() throws {
        assertSnapshot(of: hostIOS(viewModel(.partial), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "approvals.tree.partial.light.ios")
    }
    @Test func partialDarkIOS() throws {
        assertSnapshot(of: hostIOS(viewModel(.partial), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "approvals.tree.partial.dark.ios")
    }
    @Test func fullLightIOS() throws {
        assertSnapshot(of: hostIOS(viewModel(.full), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "approvals.tree.full.light.ios")
    }
    @Test func fullDarkIOS() throws {
        assertSnapshot(of: hostIOS(viewModel(.full), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "approvals.tree.full.dark.ios")
    }
    #endif
}
