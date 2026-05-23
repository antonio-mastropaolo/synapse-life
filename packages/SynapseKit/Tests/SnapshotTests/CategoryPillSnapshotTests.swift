import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Features
@testable import DesignSystem

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Visual coverage for the [[CategoryPill]] component. Renders a strip of
/// every default category at both sizes (compact + large), in both
/// schemes. The point is to lock the pill aesthetic — color + corner
/// radius + typography — so a stray edit to `CategoryID.displayColor` or
/// to the pill geometry shows up as a snapshot diff during review.
@Suite("CategoryPillSnapshot")
@MainActor
struct CategoryPillSnapshotTests {

    private var grid: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(CategoryID.defaults.enumerated()), id: \.offset) { _, id in
                HStack(spacing: 10) {
                    CategoryPill(category: id, size: .compact)
                    CategoryPill(category: id, size: .large)
                }
            }
        }
        .padding(16)
    }

    #if os(iOS)
    private func host(scheme: ColorScheme) -> UIViewController {
        let root = grid
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 520)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func iosLight() throws {
        let vc = host(scheme: .light)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "pill.ios.light")
    }
    @Test func iosDark() throws {
        let vc = host(scheme: .dark)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "pill.ios.dark")
    }
    #endif

    #if os(macOS)
    private func host(scheme: ColorScheme) -> NSView {
        let root = grid
            .frame(width: 320, height: 520)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 520)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func macLight() throws {
        let view = host(scheme: .light)
        assertSnapshot(of: view, as: .image, named: "pill.mac.light")
    }
    @Test func macDark() throws {
        let view = host(scheme: .dark)
        assertSnapshot(of: view, as: .image, named: "pill.mac.dark")
    }
    #endif
}
