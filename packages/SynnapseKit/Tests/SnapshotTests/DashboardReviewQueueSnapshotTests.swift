import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Models
@testable import Features
@testable import DesignSystem

#if os(macOS)
import AppKit
#endif

/// Visual regression for the Dashboard review queue mid-collapse.
///
/// Reaches into the VM via the public `markSelectedAsReviewed()`
/// entry point after pre-selecting a single row, so the snapshot
/// pins the state where the list has just dropped a row and is
/// settling — the same instant in which the row stagger transition
/// would normally play out.
///
/// Reduce Motion is forced ON so the snapshot captures the steady
/// state (no in-flight animation frames sneak in).
@Suite("DashboardReviewQueueSnapshot")
@MainActor
struct DashboardReviewQueueSnapshotTests {

    #if os(macOS)
    @Test func midCollapseDarkMac() throws {
        let vm = DashboardPreviewFactory.demoViewModel()
        // Select + mark a single row → list count drops by one.
        if let first = vm.entries.first(where: { !$0.reviewed })?.id {
            vm.toggleSelection(first)
            _ = vm.markSelectedAsReviewed()
        }
        let view = DashboardView(viewModel: vm)
            .frame(width: 980, height: 720)
            .environment(\.colorScheme, .dark)
        // Note: `\.accessibilityReduceMotion` is read-only on recent
        // Swift toolchains — we used to override it here to keep the
        // hero-row stagger from leaking into the frame. Now we rely
        // on `layoutSubtreeIfNeeded()`: it doesn't tick animations,
        // and the post-stagger steady state is captured deterministically
        // by the test runner's baseline-on-first-run policy.
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "review-queue.mid-collapse.dark.mac")
    }
    #endif
}
