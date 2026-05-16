import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Models
@testable import Networking
@testable import Features
@testable import DesignSystem

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 8 references = 2 platforms × 2 schemes × 2 states (list, list+inspector).
@Suite("OctagonScreenSnapshot")
@MainActor
struct OctagonScreenSnapshotTests {

    private func sampleMemberships() -> [MembershipCard] {
        [
            .init(id: "m_001", vendor: "Netflix",
                  averageAmount: Decimal(string: "15.49")!,
                  cadence: .monthly,
                  nextPredictedAt: Date(timeIntervalSince1970: 1_717_459_200),
                  lastSeenAt: Date(timeIntervalSince1970: 1_714_867_200),
                  confidence: 0.97, status: .active),
            .init(id: "m_002", vendor: "Spotify",
                  averageAmount: Decimal(string: "10.99")!,
                  cadence: .monthly,
                  nextPredictedAt: Date(timeIntervalSince1970: 1_717_459_200),
                  lastSeenAt: nil,
                  confidence: 0.95, status: .active),
            .init(id: "m_003", vendor: "Costco",
                  averageAmount: Decimal(60),
                  cadence: .yearly,
                  nextPredictedAt: nil,
                  lastSeenAt: Date(timeIntervalSince1970: 1_700_000_000),
                  confidence: 0.85, status: .active),
            .init(id: "m_004", vendor: "Adobe Creative Cloud",
                  averageAmount: Decimal(string: "54.99")!,
                  cadence: .monthly,
                  nextPredictedAt: nil,
                  lastSeenAt: nil,
                  confidence: 0.88, status: .active),
            .init(id: "m_005", vendor: "Substack Writer",
                  averageAmount: Decimal(8),
                  cadence: .monthly,
                  nextPredictedAt: nil,
                  lastSeenAt: nil,
                  confidence: 0.7, status: .canceled)
        ]
    }

    private func sampleBrief() -> OctagonVendor {
        OctagonVendor(
            vendor: "Netflix",
            legalName: "Netflix, Inc.",
            status: "public",
            yearFounded: 1997,
            employees: 13_000,
            hq: .init(city: "Los Gatos", stateProvince: "CA", country: "US"),
            primaryIndustry: "Streaming media",
            verticals: ["consumer", "media"],
            competitors: ["Disney+", "HBO Max", "Hulu"],
            lastValuationUsdM: Decimal(280_000),
            lastValuationAt: nil,
            lastFinancing: .init(type: "Public", sizeUsdM: nil, asOf: nil),
            vcRaisedUsdM: nil,
            revenueUsdM: Decimal(33_700),
            ceo: .init(name: "Ted Sarandos", email: nil),
            octagonUpdatedAt: nil
        )
    }

    private func listVM() -> OctagonViewModel {
        let api = MockOctagonAPI()
        let vm = OctagonViewModel(api: api)
        vm.injectForSnapshots(state: .ready(sampleMemberships()))
        return vm
    }

    private func listWithInspectorVM() -> OctagonViewModel {
        let api = MockOctagonAPI()
        let vm = OctagonViewModel(api: api)
        vm.injectForSnapshots(
            state: .ready(sampleMemberships()),
            inspector: .ready(sampleBrief()),
            selectedVendor: "Netflix"
        )
        return vm
    }

    #if os(macOS)
    private func hostMac<Root: View>(_ root: Root, scheme: ColorScheme) -> NSView {
        let view = root
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func listLightMac() throws {
        assertSnapshot(of: hostMac(OctagonView(viewModel: listVM()), scheme: .light),
                       as: .image, named: "octagon.list.light.mac")
    }
    @Test func listDarkMac() throws {
        assertSnapshot(of: hostMac(OctagonView(viewModel: listVM()), scheme: .dark),
                       as: .image, named: "octagon.list.dark.mac")
    }
    @Test func inspectorLightMac() throws {
        assertSnapshot(of: hostMac(OctagonView(viewModel: listWithInspectorVM()), scheme: .light),
                       as: .image, named: "octagon.inspector.light.mac")
    }
    @Test func inspectorDarkMac() throws {
        assertSnapshot(of: hostMac(OctagonView(viewModel: listWithInspectorVM()), scheme: .dark),
                       as: .image, named: "octagon.inspector.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS<Root: View>(_ root: Root, scheme: ColorScheme) -> UIViewController {
        let view = root
            .environment(\.colorScheme, scheme)
            .identity(.cockpitInstrument)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func listLightIOS() throws {
        assertSnapshot(of: hostIOS(OctagonView(viewModel: listVM()), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "octagon.list.light.ios")
    }
    @Test func listDarkIOS() throws {
        assertSnapshot(of: hostIOS(OctagonView(viewModel: listVM()), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "octagon.list.dark.ios")
    }
    @Test func inspectorLightIOS() throws {
        // On iOS the inspector arrives as a `.sheet` — snapshot the
        // standalone `OctagonInspector` view to lock the brief layout.
        let inspector = OctagonInspector(state: .ready(sampleBrief()))
        assertSnapshot(of: hostIOS(inspector, scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "octagon.inspector.light.ios")
    }
    @Test func inspectorDarkIOS() throws {
        let inspector = OctagonInspector(state: .ready(sampleBrief()))
        assertSnapshot(of: hostIOS(inspector, scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "octagon.inspector.dark.ios")
    }
    #endif
}
