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

/// Visual regression for the Dashboard v2 hero row in isolation.
///
/// The hero row is the load-bearing piece of the M9 dashboard pass —
/// every metric the user sees up top is fed by it. Snapshotting the
/// row alone (rather than just the full surface) lets us catch a
/// regression where the cards reorder, the sparkline collapses, or
/// the NEXT BILL urgency-warning loses its tone without scrolling
/// through the full mac shot.
///
/// macOS-only by repo convention; iOS snapshots are filled lazily.
@Suite("DashboardHeroRowSnapshot")
@MainActor
struct DashboardHeroRowSnapshotTests {

    #if os(macOS)
    private func makeView(scheme: ColorScheme) -> some View {
        let vm = DashboardPreviewFactory.demoViewModel()
        return DashboardHeroRow(
            widgetState: vm.widgetState,
            currency: "USD",
            openCashFlow: nil,
            openTopCategory: nil,
            openNextBill: nil,
            iconResolver: nil,
            // Forces the post-stagger steady state — what the user
            // actually sees once the cascade has finished. Without it
            // the cards would render at zero opacity (pre-appear).
            immediateAppearance: true
        )
        .padding(16)
        .frame(width: 900, height: 200)
        .background(Color.clear)
        .environment(\.colorScheme, scheme)
    }

    @Test func heroRowLightMac() throws {
        let host = NSHostingView(rootView: AnyView(makeView(scheme: .light)))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "hero-row.light.mac")
    }

    @Test func heroRowDarkMac() throws {
        let host = NSHostingView(rootView: AnyView(makeView(scheme: .dark)))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "hero-row.dark.mac")
    }
    #endif
}
