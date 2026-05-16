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

/// 12 references = 2 platforms × 2 schemes × 3 states (idle, ready+history,
/// streaming).
@Suite("AdvisorsScreenSnapshot")
@MainActor
struct AdvisorsScreenSnapshotTests {

    private func sampleAdvisors() -> [Advisor] {
        [
            Advisor(
                id: "financial", name: "Wealth Coach",
                specialty: "Budgets & cash flow",
                avatarColorHex: "#34d399", avatarInitials: "WC",
                unreadCount: 2, lastThreadId: "thr_1",
                lastSummary: "Reviewed sub renewals", lastActiveAt: Date(timeIntervalSince1970: 1_715_798_400)
            ),
            Advisor(
                id: "grant", name: "Grant Advisor",
                specialty: "NSF & university budgets",
                avatarColorHex: "#60a5fa", avatarInitials: "GA",
                unreadCount: 0
            ),
            Advisor(
                id: "consulting", name: "Consulting",
                specialty: "Hourly engagements",
                avatarColorHex: "#f472b6", avatarInitials: "CO",
                unreadCount: 1, lastThreadId: "thr_2",
                lastSummary: "WW deck progress", lastActiveAt: Date(timeIntervalSince1970: 1_715_700_000)
            ),
            Advisor(
                id: "stripe", name: "Stripe Trial",
                specialty: "Pricing & SaaS uplift",
                avatarColorHex: "#a78bfa", avatarInitials: "ST",
                unreadCount: 0
            ),
            Advisor(
                id: "discount", name: "Discount Hunter",
                specialty: "Refunds & promo codes",
                avatarColorHex: "#fb923c", avatarInitials: "DH",
                unreadCount: 0
            )
        ]
    }

    private func idleVM() -> AdvisorsListViewModel {
        let api = MockAdvisorsAPI()
        let vm = AdvisorsListViewModel(api: api)
        vm.injectForSnapshots(state: .loading)
        return vm
    }

    private func readyVM() -> AdvisorsListViewModel {
        let api = MockAdvisorsAPI()
        let vm = AdvisorsListViewModel(api: api)
        vm.injectForSnapshots(
            state: .ready(sampleAdvisors()),
            selectedAdvisorId: "financial"
        )
        return vm
    }

    private func streamingVM() -> (AdvisorsListViewModel, StreamingChatViewModel) {
        let listVM = readyVM()
        let advisor = sampleAdvisors()[0]
        let api = MockAdvisorsAPI()
        let chatVM = StreamingChatViewModel(api: api, advisor: advisor)
        chatVM.injectForSnapshots(messages: [
            ChatMessage(role: .user, content: "What's my burn this month?",
                        createdAt: Date(timeIntervalSince1970: 1_715_799_000)),
            ChatMessage(role: .assistant,
                        content: "Tracking $4,820 across 14 active subscriptions. Two stand out for cancel:",
                        createdAt: Date(timeIntervalSince1970: 1_715_799_120),
                        isStreaming: false),
            ChatMessage(role: .user, content: "Show me the two.",
                        createdAt: Date(timeIntervalSince1970: 1_715_799_180)),
            ChatMessage(role: .assistant,
                        content: "Generating analysis",
                        createdAt: Date(timeIntervalSince1970: 1_715_799_200),
                        isStreaming: true)
        ], isStreaming: true)
        return (listVM, chatVM)
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

    @Test func idleLightMac() throws {
        assertSnapshot(of: hostMac(AdvisorsView(viewModel: idleVM()), scheme: .light),
                       as: .image, named: "advisors.idle.light.mac")
    }
    @Test func idleDarkMac() throws {
        assertSnapshot(of: hostMac(AdvisorsView(viewModel: idleVM()), scheme: .dark),
                       as: .image, named: "advisors.idle.dark.mac")
    }
    @Test func readyLightMac() throws {
        assertSnapshot(of: hostMac(AdvisorsView(viewModel: readyVM()), scheme: .light),
                       as: .image, named: "advisors.ready.light.mac")
    }
    @Test func readyDarkMac() throws {
        assertSnapshot(of: hostMac(AdvisorsView(viewModel: readyVM()), scheme: .dark),
                       as: .image, named: "advisors.ready.dark.mac")
    }
    @Test func streamingLightMac() throws {
        let (listVM, chatVM) = streamingVM()
        // Render the chat pane in isolation so we get deterministic
        // streaming-state coverage that does not depend on the split-view
        // detail wiring (which doesn't snapshot cleanly on macOS).
        _ = listVM
        let pane = ChatPane(viewModel: chatVM)
        assertSnapshot(of: hostMac(pane, scheme: .light),
                       as: .image, named: "advisors.streaming.light.mac")
    }
    @Test func streamingDarkMac() throws {
        let (_, chatVM) = streamingVM()
        let pane = ChatPane(viewModel: chatVM)
        assertSnapshot(of: hostMac(pane, scheme: .dark),
                       as: .image, named: "advisors.streaming.dark.mac")
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

    @Test func idleLightIOS() throws {
        assertSnapshot(of: hostIOS(AdvisorsView(viewModel: idleVM()), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "advisors.idle.light.ios")
    }
    @Test func idleDarkIOS() throws {
        assertSnapshot(of: hostIOS(AdvisorsView(viewModel: idleVM()), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "advisors.idle.dark.ios")
    }
    @Test func readyLightIOS() throws {
        assertSnapshot(of: hostIOS(AdvisorsView(viewModel: readyVM()), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "advisors.ready.light.ios")
    }
    @Test func readyDarkIOS() throws {
        assertSnapshot(of: hostIOS(AdvisorsView(viewModel: readyVM()), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "advisors.ready.dark.ios")
    }
    @Test func streamingLightIOS() throws {
        let (_, chatVM) = streamingVM()
        let pane = ChatPane(viewModel: chatVM)
        assertSnapshot(of: hostIOS(pane, scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "advisors.streaming.light.ios")
    }
    @Test func streamingDarkIOS() throws {
        let (_, chatVM) = streamingVM()
        let pane = ChatPane(viewModel: chatVM)
        assertSnapshot(of: hostIOS(pane, scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "advisors.streaming.dark.ios")
    }
    #endif
}
