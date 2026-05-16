#if os(macOS)
import Foundation
import SwiftUI
import AppKit
import Testing
import SnapshotTesting
@testable import Models
@testable import Features
@testable import DesignSystem

// References live under Tests/SnapshotTests/__Snapshots__/ — generated once
// on the M2 milestone and committed. Subsequent runs gate on them.
// swift-snapshot-testing does NOT expose a SwiftUI .image strategy on macOS
// the way it does on iOS, so we host the view in NSHostingView and snapshot
// the resulting NSView.
@Suite("SpotlightScreenSnapshot")
@MainActor
struct SpotlightScreenSnapshotTests {

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

    private func hostView<V: View>(_ view: V, scheme: ColorScheme) -> NSView {
        let wrapped = view
            .frame(width: 720, height: 480)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let hosting = NSHostingView(rootView: wrapped)
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        // Force a layout so the snapshot renders the fully composed tree.
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test
    func loadingLight() throws {
        let view = hostView(
            SpotlightPanelView(state: .loading, selected: nil, query: ""),
            scheme: .light
        )
        assertSnapshot(of: view, as: .image)
    }

    @Test
    func loadingDark() throws {
        let view = hostView(
            SpotlightPanelView(state: .loading, selected: nil, query: ""),
            scheme: .dark
        )
        assertSnapshot(of: view, as: .image)
    }

    @Test
    func resultsLight() throws {
        let items = [
            sampleItem("a", title: "Mutation Testing for LLM-Generated Code"),
            sampleItem("b", title: "Spectral Methods for Test Selection")
        ]
        let view = hostView(
            SpotlightPanelView(state: .results(items), selected: items.first, query: "mut"),
            scheme: .light
        )
        assertSnapshot(of: view, as: .image)
    }

    @Test
    func resultsDark() throws {
        let items = [
            sampleItem("a", title: "Mutation Testing for LLM-Generated Code"),
            sampleItem("b", title: "Spectral Methods for Test Selection")
        ]
        let view = hostView(
            SpotlightPanelView(state: .results(items), selected: items.first, query: "mut"),
            scheme: .dark
        )
        assertSnapshot(of: view, as: .image)
    }

    @Test
    func emptyLight() throws {
        let view = hostView(
            SpotlightPanelView(state: .empty, selected: nil, query: "zzz"),
            scheme: .light
        )
        assertSnapshot(of: view, as: .image)
    }

    @Test
    func emptyDark() throws {
        let view = hostView(
            SpotlightPanelView(state: .empty, selected: nil, query: "zzz"),
            scheme: .dark
        )
        assertSnapshot(of: view, as: .image)
    }
}
#endif
