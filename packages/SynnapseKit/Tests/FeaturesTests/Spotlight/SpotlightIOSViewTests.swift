#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Models
@testable import Features

/// We deliberately do NOT use ViewInspector. The contract we care about is:
/// the cross-platform `SpotlightView` is a thin shell over `SpotlightViewModel`,
/// so we drive the view model behind it and assert observable state. The
/// rendering itself is covered by the iOS snapshot suite.
@Suite("SpotlightIOSView")
@MainActor
struct SpotlightIOSViewTests {

    private func makeItem(_ id: String, _ title: String) -> SpotlightItem {
        SpotlightItem(
            id: id,
            messageId: "m-\(id)",
            kind: "pick",
            issueLabel: "ISSUE-2026-05-MAY",
            summary: title,
            runLink: nil,
            paperUrl: URL(string: "https://arxiv.org/abs/2505.0001"),
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

    @Test
    func mountingWithKnownPageProducesResultsState() async throws {
        let api = MockSpotlightAPI()
        let items = [
            makeItem("a", "Mutation Testing for LLM-Generated Code"),
            makeItem("b", "Spectral Methods for Test Selection")
        ]
        await api.setNextPage(SpotlightPage(events: items, nextCursor: nil))
        let vm = SpotlightViewModel(api: api, debounce: .milliseconds(10))

        // Mount the iOS view so SwiftUI's layout/owner-graph wakes the
        // `.task` modifier path indirectly. We still drive refresh explicitly
        // because we want a deterministic test, not a wall-clock dependency.
        let host = UIHostingController(rootView: SpotlightView(viewModel: vm))
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.layoutIfNeeded()

        await vm.refresh()

        if case .results(let got) = vm.state {
            #expect(got.map(\.id) == ["a", "b"])
        } else {
            Issue.record("expected results state, got \(vm.state)")
        }
    }

    @Test
    func tappingARowSelectsTheItem() async throws {
        let api = MockSpotlightAPI()
        let items = [makeItem("a", "Mutation Testing")]
        await api.setNextPage(SpotlightPage(events: items, nextCursor: nil))
        let vm = SpotlightViewModel(api: api, debounce: .milliseconds(10))
        await vm.refresh()

        let host = UIHostingController(rootView: SpotlightView(viewModel: vm))
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.layoutIfNeeded()

        // The view's row binding is on the view model. Simulate the tap by
        // calling the same entry point the view's `NavigationLink` does.
        vm.select(items[0])
        #expect(vm.selected?.id == "a")
    }
}
#endif
