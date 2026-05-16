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

/// Snapshot references for `ApprovalsFlatView`. 16 total — 4 states (loading,
/// empty, populated, populated-with-selection) × 2 schemes × 2 platforms
/// (macOS, iOS). See memory `feedback_snapshot_macos`: macOS lacks a SwiftUI
/// `.image` strategy, so we wrap views in `NSHostingView` and snapshot the
/// resulting `NSView`.
@Suite("ApprovalsFlatScreenSnapshot")
@MainActor
struct ApprovalsFlatScreenSnapshotTests {

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
                validUntil: Date(timeIntervalSince1970: 1_771_161_600),
                status: .approved,
                workdayURL: URL(string: "https://wd5.myworkday.com/wm/d/inst/1/expense"),
                totalAmount: Decimal(string: "412.55"),
                currency: "USD"
            ),
            Approval(
                id: "ap-openai",
                title: "Re: OpenAI API spend (pending)",
                vendor: "OpenAI",
                approver: "Jacqulyn Ledger",
                approverRole: "admin-coordinator",
                category: "ai-tools",
                requestedAt: Date(timeIntervalSince1970: 1_730_000_000),
                validUntil: Date(timeIntervalSince1970: 1_761_536_000),
                status: .pending,
                workdayURL: nil,
                totalAmount: Decimal(string: "187.20"),
                currency: "USD"
            )
        ]
        let receipts = [
            Receipt(id: "r1", approvalId: "ap-anthropic", vendor: "Anthropic",
                    amount: Decimal(string: "200.00"), currency: "USD",
                    date: "2026-02-10", documentKind: .receipt,
                    sourceAccount: "amastropaolo@wm.edu", submissionStatus: "pending"),
            Receipt(id: "r2", approvalId: "ap-anthropic", vendor: "Anthropic",
                    amount: Decimal(string: "212.55"), currency: "USD",
                    date: "2026-03-12", documentKind: .receipt,
                    sourceAccount: "amastropaolo@wm.edu", submissionStatus: "pending")
        ]
        return ApprovalsBundle(approvals: approvals, receipts: receipts)
    }

    private func loadedViewModel(selected: Bool) -> ApprovalsViewModel {
        let mock = MockApprovalsAPI()
        let vm = ApprovalsViewModel(api: mock)
        let bundle = sampleBundle()
        vm.injectForSnapshots(state: .results(bundle.approvals), bundle: bundle)
        if selected, let first = bundle.approvals.first {
            vm.select(first)
        }
        return vm
    }

    private func loadingViewModel() -> ApprovalsViewModel {
        let mock = MockApprovalsAPI()
        let vm = ApprovalsViewModel(api: mock)
        vm.injectForSnapshots(state: .loading, bundle: nil)
        return vm
    }

    private func emptyViewModel() -> ApprovalsViewModel {
        let mock = MockApprovalsAPI()
        let vm = ApprovalsViewModel(api: mock)
        vm.injectForSnapshots(state: .empty, bundle: ApprovalsBundle(approvals: [], receipts: []))
        return vm
    }

    #if os(macOS)
    private func hostMac(_ vm: ApprovalsViewModel, scheme: ColorScheme) -> NSView {
        let view = ApprovalsFlatView(viewModel: vm)
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func loadingLightMac() throws {
        assertSnapshot(of: hostMac(loadingViewModel(), scheme: .light), as: .image,
                       named: "approvals.flat.loading.light.mac")
    }
    @Test func loadingDarkMac() throws {
        assertSnapshot(of: hostMac(loadingViewModel(), scheme: .dark), as: .image,
                       named: "approvals.flat.loading.dark.mac")
    }
    @Test func emptyLightMac() throws {
        assertSnapshot(of: hostMac(emptyViewModel(), scheme: .light), as: .image,
                       named: "approvals.flat.empty.light.mac")
    }
    @Test func emptyDarkMac() throws {
        assertSnapshot(of: hostMac(emptyViewModel(), scheme: .dark), as: .image,
                       named: "approvals.flat.empty.dark.mac")
    }
    @Test func populatedLightMac() throws {
        assertSnapshot(of: hostMac(loadedViewModel(selected: false), scheme: .light), as: .image,
                       named: "approvals.flat.populated.light.mac")
    }
    @Test func populatedDarkMac() throws {
        assertSnapshot(of: hostMac(loadedViewModel(selected: false), scheme: .dark), as: .image,
                       named: "approvals.flat.populated.dark.mac")
    }
    @Test func selectedLightMac() throws {
        assertSnapshot(of: hostMac(loadedViewModel(selected: true), scheme: .light), as: .image,
                       named: "approvals.flat.selected.light.mac")
    }
    @Test func selectedDarkMac() throws {
        assertSnapshot(of: hostMac(loadedViewModel(selected: true), scheme: .dark), as: .image,
                       named: "approvals.flat.selected.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ vm: ApprovalsViewModel, scheme: ColorScheme) -> UIViewController {
        let view = ApprovalsFlatView(viewModel: vm)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func loadingLightIOS() throws {
        assertSnapshot(of: hostIOS(loadingViewModel(), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.loading.light.ios")
    }
    @Test func loadingDarkIOS() throws {
        assertSnapshot(of: hostIOS(loadingViewModel(), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.loading.dark.ios")
    }
    @Test func emptyLightIOS() throws {
        assertSnapshot(of: hostIOS(emptyViewModel(), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.empty.light.ios")
    }
    @Test func emptyDarkIOS() throws {
        assertSnapshot(of: hostIOS(emptyViewModel(), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.empty.dark.ios")
    }
    @Test func populatedLightIOS() throws {
        assertSnapshot(of: hostIOS(loadedViewModel(selected: false), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.populated.light.ios")
    }
    @Test func populatedDarkIOS() throws {
        assertSnapshot(of: hostIOS(loadedViewModel(selected: false), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.populated.dark.ios")
    }
    @Test func selectedLightIOS() throws {
        assertSnapshot(of: hostIOS(loadedViewModel(selected: true), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.selected.light.ios")
    }
    @Test func selectedDarkIOS() throws {
        assertSnapshot(of: hostIOS(loadedViewModel(selected: true), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "approvals.flat.selected.dark.ios")
    }
    #endif
}
