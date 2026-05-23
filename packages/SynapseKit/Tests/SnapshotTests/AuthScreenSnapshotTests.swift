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

@Suite("AuthScreenSnapshot")
@MainActor
struct AuthScreenSnapshotTests {

    #if os(iOS)
    private func host(scheme: ColorScheme) -> UIViewController {
        let root = SignInView(onTapSignIn: {})
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func iosLight() throws {
        let vc = host(scheme: .light)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "signin.ios.light")
    }
    @Test func iosDark() throws {
        let vc = host(scheme: .dark)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "signin.ios.dark")
    }
    #endif

    #if os(macOS)
    private func host(scheme: ColorScheme) -> NSView {
        let root = SignInView(onTapSignIn: {})
            .frame(width: 640, height: 480)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func macLight() throws {
        let view = host(scheme: .light)
        assertSnapshot(of: view, as: .image, named: "signin.mac.light")
    }
    @Test func macDark() throws {
        let view = host(scheme: .dark)
        assertSnapshot(of: view, as: .image, named: "signin.mac.dark")
    }
    #endif
}
