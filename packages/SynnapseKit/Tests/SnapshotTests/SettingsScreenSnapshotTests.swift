import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Auth
@testable import Models
@testable import Networking
@testable import Features
@testable import DesignSystem

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Snapshot references for the M9 Settings surfaces. 4 refs:
///   - macOS settings scene × {light, dark}
///   - iOS settings form × {light, dark}
///
/// The auth view model is built against an in-memory session store and
/// stays signed out — that's the visual state most contributors land in
/// when they first open Settings.
@Suite("SettingsScreenSnapshot")
@MainActor
struct SettingsScreenSnapshotTests {

    private func settingsVM() -> SettingsViewModel {
        let store = InMemorySettingsStore(initial: SettingsSnapshot(
            apiBaseURL: "http://localhost:3000/",
            concealBalances: true,
            reduceMotionPreview: false,
            spotlightHotkey: "Cmd + Shift + Space"
        ))
        return SettingsViewModel(store: store)
    }

    private func authVM() -> AuthViewModel {
        // Real AuthViewModel against a mock session API + isolated keychain
        // service so the snapshot lands deterministically on the "signed
        // out" state.
        let mock = MockSessionAPI()
        let store = SessionStore(service: "tech.synnapse.settings.snapshot.\(UUID().uuidString)")
        return AuthViewModel(api: mock, store: store)
    }

    #if os(macOS)
    private func hostMac(_ view: some View, scheme: ColorScheme,
                         width: CGFloat = 480, height: CGFloat = 360) -> NSView {
        let host = NSHostingView(rootView: AnyView(
            view
                .frame(width: width, height: height)
                .environment(\.colorScheme, scheme)
                .identity(.default)
        ))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test func sceneLightMac() throws {
        let view = SettingsScene(settings: settingsVM(), auth: authVM())
        assertSnapshot(of: hostMac(view, scheme: .light), as: .image,
                       named: "settings.scene.light.mac")
    }

    @Test func sceneDarkMac() throws {
        let view = SettingsScene(settings: settingsVM(), auth: authVM())
        assertSnapshot(of: hostMac(view, scheme: .dark), as: .image,
                       named: "settings.scene.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ view: some View, scheme: ColorScheme) -> UIViewController {
        let host = UIHostingController(rootView: AnyView(
            NavigationStack { view }
                .environment(\.colorScheme, scheme)
                .identity(.default)
        ))
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func formLightIOS() throws {
        let view = SettingsForm(settings: settingsVM(), auth: authVM())
        assertSnapshot(of: hostIOS(view, scheme: .light),
                       as: .image(on: .iPhone13Pro),
                       named: "settings.form.light.ios")
    }

    @Test func formDarkIOS() throws {
        let view = SettingsForm(settings: settingsVM(), auth: authVM())
        assertSnapshot(of: hostIOS(view, scheme: .dark),
                       as: .image(on: .iPhone13Pro),
                       named: "settings.form.dark.ios")
    }
    #endif
}
