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

/// Snapshot references for [[InboxListView]]. Two states per scheme per
/// platform: empty / results. 8 refs total — 2 × 2 × 2.
@Suite("InboxScreenSnapshot")
@MainActor
struct InboxScreenSnapshotTests {

    private func sampleItems() -> [InboxItem] {
        [
            InboxItem(
                id: "m-1", source: .gmail, threadId: "t-1",
                sender: "jled@wm.edu", senderDisplay: "Jacqulyn Ledger",
                subject: "Re: Anthropic spend",
                body: "Approved — go ahead and submit when ready.",
                bodyPreview: "Approved — go ahead and submit when ready.",
                receivedAt: Date(timeIntervalSince1970: 1_747_000_000),
                isRead: false
            ),
            InboxItem(
                id: "m-2", source: .gmail, threadId: nil,
                sender: "no-reply@stripe.com", senderDisplay: "Stripe",
                subject: "Your invoice INV-0012",
                body: "Attached: invoice for May.",
                bodyPreview: "Attached: invoice for May.",
                receivedAt: Date(timeIntervalSince1970: 1_746_500_000),
                isRead: false
            ),
            InboxItem(
                id: "m-3", source: .outlook, threadId: nil,
                sender: "advisor@wm.edu", senderDisplay: "Faculty Advisor",
                subject: "RTF advice",
                body: "Following up on the conversation last week...",
                bodyPreview: "Following up on the conversation last week...",
                receivedAt: Date(timeIntervalSince1970: 1_746_000_000),
                isRead: true
            )
        ]
    }

    private func loadedVM() -> InboxListViewModel {
        let mock = MockInboxAPI()
        let vm = InboxListViewModel(api: mock)
        let items = sampleItems()
        vm.injectForSnapshots(state: .results(items), items: items)
        return vm
    }

    private func emptyVM() -> InboxListViewModel {
        let mock = MockInboxAPI()
        let vm = InboxListViewModel(api: mock)
        vm.injectForSnapshots(state: .empty, items: [])
        return vm
    }

    #if os(macOS)
    private func hostMac(_ vm: InboxListViewModel, scheme: ColorScheme) -> NSView {
        let view = InboxListView(viewModel: vm)
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func emptyLightMac() throws {
        assertSnapshot(of: hostMac(emptyVM(), scheme: .light), as: .image,
                       named: "inbox.empty.light.mac")
    }
    @Test func emptyDarkMac() throws {
        assertSnapshot(of: hostMac(emptyVM(), scheme: .dark), as: .image,
                       named: "inbox.empty.dark.mac")
    }
    @Test func resultsLightMac() throws {
        assertSnapshot(of: hostMac(loadedVM(), scheme: .light), as: .image,
                       named: "inbox.results.light.mac")
    }
    @Test func resultsDarkMac() throws {
        assertSnapshot(of: hostMac(loadedVM(), scheme: .dark), as: .image,
                       named: "inbox.results.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ vm: InboxListViewModel, scheme: ColorScheme) -> UIViewController {
        let view = InboxListView(viewModel: vm)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func emptyLightIOS() throws {
        assertSnapshot(of: hostIOS(emptyVM(), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "inbox.empty.light.ios")
    }
    @Test func emptyDarkIOS() throws {
        assertSnapshot(of: hostIOS(emptyVM(), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "inbox.empty.dark.ios")
    }
    @Test func resultsLightIOS() throws {
        assertSnapshot(of: hostIOS(loadedVM(), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "inbox.results.light.ios")
    }
    @Test func resultsDarkIOS() throws {
        assertSnapshot(of: hostIOS(loadedVM(), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "inbox.results.dark.ios")
    }
    #endif
}
