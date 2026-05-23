import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Models
@testable import Networking
@testable import Features
@testable import DesignSystem

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// LIFE Terminal snapshot references. Three states × two platforms = six
/// PNGs. States:
///   - dark (default rendering, shader path)
///   - light (still renders — LIFE is identity, not color scheme — but
///     the system color scheme is light, so the host environment passes
///     light through to the view)
///   - reduce-motion-dark (forces the Canvas fallback path)
///
/// We host in NSHostingView / UIHostingController per platform, matching
/// the pattern established by the Spotlight + Finance snapshot suites.
/// The Metal background plate is replaced by the Canvas fallback in the
/// reduce-motion variant; the other variants render the shader plate
/// only on hosts that have a Metal device — on Linux CI without a GPU,
/// SwiftPM's tests still pass because `LifeTerminalViewMetal` falls
/// through to the ink color when MetalKit is unavailable.
@MainActor
@Suite("LifeTerminalScreenSnapshot")
struct LifeTerminalScreenSnapshotTests {

    private func sampleEntries() -> [LifeEntry] {
        let base: TimeInterval = 1_747_407_000
        return [
            LifeEntry(
                id: "boot",
                timestamp: Date(timeIntervalSince1970: base - 600),
                kind: .boot,
                text: "SYNAPSE LIFE TERMINAL v1.0 — feed online"
            ),
            LifeEntry(
                id: "t1",
                timestamp: Date(timeIntervalSince1970: base),
                kind: .transaction,
                text: "Whole Foods Market — $42.18"
            ),
            LifeEntry(
                id: "t2",
                timestamp: Date(timeIntervalSince1970: base + 120),
                kind: .transaction,
                text: "Anthropic API — $7.40"
            ),
            LifeEntry(
                id: "b1",
                timestamp: Date(timeIntervalSince1970: base + 240),
                kind: .bill,
                text: "Verizon Wireless due in 3 days — $84.91"
            ),
            LifeEntry(
                id: "i1",
                timestamp: Date(timeIntervalSince1970: base + 360),
                kind: .insight,
                text: "MTD spend on track: 18 of 31 days, $1,204"
            ),
            LifeEntry(
                id: "s1",
                timestamp: Date(timeIntervalSince1970: base + 480),
                kind: .streak,
                text: "12-day budget streak intact"
            )
        ]
    }

    /// Frozen instant for all snapshot variants. Anchor:
    /// 2026-05-17 12:34:56 UTC. Picked so the stats line reads
    /// "[2026-05-17 12:34:56 UTC] up 00:00:00 · mem N.N GiB" with
    /// `launchedAt == frozen` (uptime zero) — stable on any machine.
    private let frozenInstant = Date(timeIntervalSince1970: 1_779_021_296)

    private func makeViewModel(
        reduceMotion: Bool,
        entries: [LifeEntry] = []
    ) -> LifeViewModel {
        let vm = LifeViewModel(
            api: MockLifeAPI(),
            launchedAt: frozenInstant
        )
        if !entries.isEmpty {
            vm.injectStateForSnapshots(.ready(entries))
        }
        // If entries empty, leave state `.idle` — `bufferEntries()` maps
        // that to `[]` so the boot banner + empty-state footer render.
        vm.updateRenderPath(
            accessibility: LifeAccessibilityEnvironment(reduceMotion: reduceMotion)
        )
        return vm
    }

    #if os(macOS)

    private func host(_ vm: LifeViewModel, scheme: ColorScheme, size: CGSize) -> NSView {
        let root = LifeTerminalView(
            viewModel: vm,
            frozenInstantForSnapshots: frozenInstant
        )
            .identity(.terminalAmber)
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private let macSize = CGSize(width: 720, height: 480)

    @Test
    func darkMac() throws {
        // "with-entries" variant on macOS — full feed + banner + stats.
        let vm = makeViewModel(reduceMotion: false, entries: sampleEntries())
        let view = host(vm, scheme: .dark, size: macSize)
        assertSnapshot(of: view, as: .image, named: "dark.mac")
    }

    @Test
    func lightMac() throws {
        let vm = makeViewModel(reduceMotion: false, entries: sampleEntries())
        let view = host(vm, scheme: .light, size: macSize)
        assertSnapshot(of: view, as: .image, named: "light.mac")
    }

    @Test
    func reduceMotionMac() throws {
        // Forces Canvas fallback (no shader) but the boot banner +
        // stats line + footer still render — the regression we shipped
        // this fix for was the pure-orange paint, not motion handling.
        let vm = makeViewModel(reduceMotion: true, entries: sampleEntries())
        let view = host(vm, scheme: .dark, size: macSize)
        assertSnapshot(of: view, as: .image, named: "reduceMotion.mac")
    }

    @Test
    func bootBannerZeroEntriesMac() throws {
        // The "fixed" baseline: zero entries, shader path live. Must
        // show the 4-line banner, the empty-state footer, the prompt
        // line, and the system stats line — never a blank orange plate.
        let vm = makeViewModel(reduceMotion: false, entries: [])
        let view = host(vm, scheme: .dark, size: macSize)
        assertSnapshot(of: view, as: .image, named: "bootBanner-zero-entries.mac")
    }

    #else

    private func host(_ vm: LifeViewModel, scheme: ColorScheme, size: CGSize) -> UIViewController {
        let root = LifeTerminalView(
            viewModel: vm,
            frozenInstantForSnapshots: frozenInstant
        )
            .identity(.terminalAmber)
            .environment(\.colorScheme, scheme)
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.layoutIfNeeded()
        return controller
    }

    private let iosSize = CGSize(width: 402, height: 874)

    @Test
    func darkIOS() throws {
        let vm = makeViewModel(reduceMotion: false, entries: sampleEntries())
        let vc = host(vm, scheme: .dark, size: iosSize)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "dark.ios")
    }

    @Test
    func lightIOS() throws {
        let vm = makeViewModel(reduceMotion: false, entries: sampleEntries())
        let vc = host(vm, scheme: .light, size: iosSize)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "light.ios")
    }

    @Test
    func reduceMotionIOS() throws {
        let vm = makeViewModel(reduceMotion: true, entries: sampleEntries())
        let vc = host(vm, scheme: .dark, size: iosSize)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "reduceMotion.ios")
    }

    @Test
    func bootBannerZeroEntriesIOS() throws {
        let vm = makeViewModel(reduceMotion: false, entries: [])
        let vc = host(vm, scheme: .dark, size: iosSize)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro), named: "bootBanner-zero-entries.ios")
    }

    #endif
}
