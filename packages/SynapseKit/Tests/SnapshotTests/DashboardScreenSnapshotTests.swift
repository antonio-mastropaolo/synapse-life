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

/// Visual regression references for the Copilot-inspired Dashboard.
///
/// macOS: full two-pane layout (list + inspector) at the cockpit window
/// size. iOS: list with the floating "Mark N" FAB at iPhone 13 Pro size.
/// Both schemes are captured so the gain/loss + accent palettes are
/// covered.
@Suite("DashboardScreenSnapshot")
@MainActor
struct DashboardScreenSnapshotTests {

    /// Demo VM with two rows pre-selected so the footer button paints
    /// in its enabled state and the FAB is visible on iOS.
    private func viewModelWithSelection() -> DashboardViewModel {
        let vm = DashboardPreviewFactory.demoViewModel()
        // Pick the first two ids deterministically.
        let firstTwo = vm.entries.prefix(2).map(\.id)
        for id in firstTwo { vm.toggleSelection(id) }
        return vm
    }

    #if os(macOS)
    @Test func dashboardLightMac() throws {
        let vm = viewModelWithSelection()
        let view = DashboardView(viewModel: vm)
            .frame(width: 980, height: 720)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "dashboard.light.mac")
    }

    @Test func dashboardDarkMac() throws {
        let vm = viewModelWithSelection()
        let view = DashboardView(viewModel: vm)
            .frame(width: 980, height: 720)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "dashboard.dark.mac")
    }

    @Test func dashboardInboxZeroMac() throws {
        let vm = DashboardViewModel(
            entries: [],
            ledgerTotal: 3204,
            calendar: DashboardDemoData.calendar,
            referenceDate: DashboardDemoData.referenceDate,
            locale: Locale(identifier: "en_US_POSIX")
        )
        let view = DashboardView(viewModel: vm)
            .frame(width: 980, height: 720)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "dashboard.inbox-zero.mac")
    }
    #endif

    #if os(iOS)
    @Test func dashboardLightIOS() throws {
        let vm = viewModelWithSelection()
        let view = DashboardView(viewModel: vm)
            .environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: AnyView(view))
        host.overrideUserInterfaceStyle = .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        assertSnapshot(
            of: host, as: .image(on: .iPhone13Pro),
            named: "dashboard.light.ios"
        )
    }

    @Test func dashboardDarkIOS() throws {
        let vm = viewModelWithSelection()
        let view = DashboardView(viewModel: vm)
            .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: AnyView(view))
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        assertSnapshot(
            of: host, as: .image(on: .iPhone13Pro),
            named: "dashboard.dark.ios"
        )
    }
    #endif
}
