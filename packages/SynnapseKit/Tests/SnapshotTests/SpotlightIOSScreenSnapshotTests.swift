#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
@testable import Models
@testable import Features
@testable import DesignSystem

/// iOS snapshot references for the cross-platform `SpotlightView`. We render
/// the same view in three states (loading, results, empty), in both color
/// schemes, on iPhone 16 Pro and iPad (11-inch) frames — 12 references total.
/// We use a fixed-frame `UIHostingController` rather than `.image(on: .iPhone…)`
/// device specs because we want determinism across Xcode/sim versions; the
/// drawable bounds are pinned by the operator.
@Suite("SpotlightIOSScreenSnapshot")
@MainActor
struct SpotlightIOSScreenSnapshotTests {

    private struct Frame {
        let name: String
        let size: CGSize
    }
    private let iphone16Pro = Frame(name: "iphone16pro", size: CGSize(width: 402, height: 874))
    private let ipad11 = Frame(name: "ipad11", size: CGSize(width: 834, height: 1194))

    private func sampleItem(_ id: String, title: String) -> SpotlightItem {
        SpotlightItem(
            id: id,
            messageId: "m-\(id)",
            kind: "pick",
            issueLabel: "ISSUE-2026-05-MAY",
            summary: title,
            runLink: nil,
            paperUrl: URL(string: "https://arxiv.org/abs/2505.01234"),
            overleafUrl: nil,
            status: "pending",
            detectedAt: Date(timeIntervalSince1970: 1_715_350_800),
            decidedAt: nil,
            message: .init(
                senderDisplay: "ArXiv",
                sender: "x@arxiv.org",
                subject: title,
                receivedAt: Date(timeIntervalSince1970: 1_715_347_200),
                body: nil,
                threadId: nil
            )
        )
    }

    private func host(
        state: SpotlightState,
        scheme: ColorScheme,
        size: CGSize
    ) -> UIViewController {
        let api = MockSpotlightAPI()
        let vm = SpotlightViewModel(api: api, debounce: .milliseconds(10))
        vm.injectStateForSnapshots(state)
        let root = SpotlightView(viewModel: vm)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        return host
    }

    private func resultsItems() -> [SpotlightItem] {
        [
            sampleItem("a", title: "Mutation Testing for LLM-Generated Code"),
            sampleItem("b", title: "Spectral Methods for Test Selection")
        ]
    }

    @Test func loadingLightIPhone() throws {
        let vc = host(state: .loading, scheme: .light, size: iphone16Pro.size)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "loading.light.iphone16pro")
    }
    @Test func loadingDarkIPhone() throws {
        let vc = host(state: .loading, scheme: .dark, size: iphone16Pro.size)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "loading.dark.iphone16pro")
    }
    @Test func resultsLightIPhone() throws {
        let vc = host(state: .results(resultsItems()), scheme: .light, size: iphone16Pro.size)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "results.light.iphone16pro")
    }
    @Test func resultsDarkIPhone() throws {
        let vc = host(state: .results(resultsItems()), scheme: .dark, size: iphone16Pro.size)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "results.dark.iphone16pro")
    }
    @Test func emptyLightIPhone() throws {
        let vc = host(state: .empty, scheme: .light, size: iphone16Pro.size)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "empty.light.iphone16pro")
    }
    @Test func emptyDarkIPhone() throws {
        let vc = host(state: .empty, scheme: .dark, size: iphone16Pro.size)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "empty.dark.iphone16pro")
    }

    @Test func loadingLightIPad() throws {
        let vc = host(state: .loading, scheme: .light, size: ipad11.size)
        assertSnapshot(of: vc, as: .image(on: .iPadPro11(.portrait)), named: "loading.light.ipad11")
    }
    @Test func loadingDarkIPad() throws {
        let vc = host(state: .loading, scheme: .dark, size: ipad11.size)
        assertSnapshot(of: vc, as: .image(on: .iPadPro11(.portrait)), named: "loading.dark.ipad11")
    }
    @Test func resultsLightIPad() throws {
        let vc = host(state: .results(resultsItems()), scheme: .light, size: ipad11.size)
        assertSnapshot(of: vc, as: .image(on: .iPadPro11(.portrait)), named: "results.light.ipad11")
    }
    @Test func resultsDarkIPad() throws {
        let vc = host(state: .results(resultsItems()), scheme: .dark, size: ipad11.size)
        assertSnapshot(of: vc, as: .image(on: .iPadPro11(.portrait)), named: "results.dark.ipad11")
    }
    @Test func emptyLightIPad() throws {
        let vc = host(state: .empty, scheme: .light, size: ipad11.size)
        assertSnapshot(of: vc, as: .image(on: .iPadPro11(.portrait)), named: "empty.light.ipad11")
    }
    @Test func emptyDarkIPad() throws {
        let vc = host(state: .empty, scheme: .dark, size: ipad11.size)
        assertSnapshot(of: vc, as: .image(on: .iPadPro11(.portrait)), named: "empty.dark.ipad11")
    }
}
#endif
