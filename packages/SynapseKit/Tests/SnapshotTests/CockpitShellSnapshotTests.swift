import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import DesignSystem

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// References for the Cockpit Dense app-wide shell.
///
/// Four PNGs total: macOS RootView × {light, dark} + iOS RootView × {light, dark}.
/// The shell is rendered WITHOUT applying any `.identity(...)` modifier so we
/// exercise the new environment default (Cockpit) rather than the legacy
/// `.default` token set. The snapshot encodes:
///   - sidebar with tree-style disclosure groups (FINANCE w/ three
///     sub-rows, LIFE, ADVISORS),
///   - ledger-stripe content area with monospaced section labels,
///   - signed-delta accents (gain/loss) in the finance preview row.
///
/// `RootView()` is parameter-free and renders deterministic preview content.
/// The shell's binding to live view models is done in the app entry points,
/// not in the shared shell.
@Suite("CockpitShellSnapshot")
@MainActor
struct CockpitShellSnapshotTests {

    // RootView is the shared cross-platform shell. It lives in
    // apps/Shared/RootView.swift; the snapshot test imports it transitively
    // by reaching for the host module. We declare a local typealias to
    // dodge importing the apps target into the test target.

    #if os(macOS)
    @Test func rootShellLightMac() throws {
        let view = makeRoot()
            .frame(width: 1280, height: 800)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "cockpit.shell.light.mac")
    }

    @Test func rootShellDarkMac() throws {
        let view = makeRoot()
            .frame(width: 1280, height: 800)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        host.layoutSubtreeIfNeeded()
        assertSnapshot(of: host, as: .image, named: "cockpit.shell.dark.mac")
    }
    #endif

    #if os(iOS)
    @Test func rootShellLightIOS() throws {
        let view = makeRoot()
            .environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: AnyView(view))
        host.overrideUserInterfaceStyle = .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro),
                       named: "cockpit.shell.light.ios")
    }

    @Test func rootShellDarkIOS() throws {
        let view = makeRoot()
            .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: AnyView(view))
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro),
                       named: "cockpit.shell.dark.ios")
    }
    #endif

    // MARK: - Helpers

    /// Builds the cockpit shell as the snapshot subject. The cross-platform
    /// shell lives in `apps/Shared/RootView.swift`; we reach for it via the
    /// thin `CockpitShellPreview` re-export inside DesignSystem so the test
    /// target does not need to import an app target.
    private func makeRoot() -> some View {
        CockpitShellPreview()
    }
}
