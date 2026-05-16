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

/// Snapshot references for [[PeopleView]]. Three states per scheme per
/// platform: empty / results / with-selection. 12 refs total — 3 × 2 × 2.
/// macOS uses an `NSHostingView` wrapper (memory `feedback_snapshot_macos`);
/// iOS uses `.image(on: .iPhone13Pro)` to match the rest of the suite.
@Suite("PeopleScreenSnapshot")
@MainActor
struct PeopleScreenSnapshotTests {

    private func samplePeople() -> [Person] {
        [
            Person(
                identity: "amastropaolo@wm.edu",
                displayName: "Antonio Mastropaolo",
                importanceWeight: 0.9, autoBoost: 0.0, effectiveWeight: 0.9,
                blacklisted: false, notes: "advisor",
                totalMessages: 412,
                firstSeen: Date(timeIntervalSince1970: 1_723_000_000),
                lastSeen: Date(timeIntervalSince1970: 1_747_000_000),
                distinctThreads: 87, awaitingMyReply: 3, openActions: 5,
                sources: [.gmail, .calendar], avgImportance: 0.62,
                avatarURL: nil, avatarStatus: .pending, kind: .person
            ),
            Person(
                identity: "jled@wm.edu", displayName: "Jacqulyn Ledger",
                importanceWeight: 0.9, autoBoost: 0.0, effectiveWeight: 0.9,
                blacklisted: false, notes: nil,
                totalMessages: 38,
                firstSeen: Date(timeIntervalSince1970: 1_722_000_000),
                lastSeen: Date(timeIntervalSince1970: 1_746_000_000),
                distinctThreads: 12, awaitingMyReply: 0, openActions: 2,
                sources: [.gmail], avgImportance: 0.55,
                avatarURL: nil, avatarStatus: nil, kind: .person
            ),
            Person(
                identity: "no-reply@stripe.com", displayName: "Stripe",
                importanceWeight: 0.1, autoBoost: 0.0, effectiveWeight: 0.1,
                blacklisted: false, notes: nil,
                totalMessages: 7, firstSeen: nil, lastSeen: nil,
                distinctThreads: 4, awaitingMyReply: 0, openActions: 0,
                sources: [.gmail], avgImportance: 0.05,
                avatarURL: nil, avatarStatus: nil, kind: .entity
            )
        ]
    }

    private func loadedVM(selected: Bool) -> PeopleViewModel {
        let mock = MockPeopleAPI()
        let vm = PeopleViewModel(api: mock)
        let people = samplePeople()
        vm.injectForSnapshots(state: .results(people), people: people)
        if selected { vm.select(people[0]) }
        return vm
    }

    private func emptyVM() -> PeopleViewModel {
        let mock = MockPeopleAPI()
        let vm = PeopleViewModel(api: mock)
        vm.injectForSnapshots(state: .empty, people: [])
        return vm
    }

    #if os(macOS)
    private func hostMac(_ vm: PeopleViewModel, scheme: ColorScheme) -> NSView {
        let view = PeopleView(viewModel: vm)
            .frame(width: 1100, height: 640)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 640)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func emptyLightMac() throws {
        assertSnapshot(of: hostMac(emptyVM(), scheme: .light), as: .image,
                       named: "people.empty.light.mac")
    }
    @Test func emptyDarkMac() throws {
        assertSnapshot(of: hostMac(emptyVM(), scheme: .dark), as: .image,
                       named: "people.empty.dark.mac")
    }
    @Test func resultsLightMac() throws {
        assertSnapshot(of: hostMac(loadedVM(selected: false), scheme: .light), as: .image,
                       named: "people.results.light.mac")
    }
    @Test func resultsDarkMac() throws {
        assertSnapshot(of: hostMac(loadedVM(selected: false), scheme: .dark), as: .image,
                       named: "people.results.dark.mac")
    }
    @Test func selectedLightMac() throws {
        assertSnapshot(of: hostMac(loadedVM(selected: true), scheme: .light), as: .image,
                       named: "people.selected.light.mac")
    }
    @Test func selectedDarkMac() throws {
        assertSnapshot(of: hostMac(loadedVM(selected: true), scheme: .dark), as: .image,
                       named: "people.selected.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ vm: PeopleViewModel, scheme: ColorScheme) -> UIViewController {
        let view = PeopleView(viewModel: vm)
            .environment(\.colorScheme, scheme)
            .identity(.editorial)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func emptyLightIOS() throws {
        assertSnapshot(of: hostIOS(emptyVM(), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "people.empty.light.ios")
    }
    @Test func emptyDarkIOS() throws {
        assertSnapshot(of: hostIOS(emptyVM(), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "people.empty.dark.ios")
    }
    @Test func resultsLightIOS() throws {
        assertSnapshot(of: hostIOS(loadedVM(selected: false), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "people.results.light.ios")
    }
    @Test func resultsDarkIOS() throws {
        assertSnapshot(of: hostIOS(loadedVM(selected: false), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "people.results.dark.ios")
    }
    @Test func selectedLightIOS() throws {
        assertSnapshot(of: hostIOS(loadedVM(selected: true), scheme: .light),
                       as: .image(on: .iPhone13Pro), named: "people.selected.light.ios")
    }
    @Test func selectedDarkIOS() throws {
        assertSnapshot(of: hostIOS(loadedVM(selected: true), scheme: .dark),
                       as: .image(on: .iPhone13Pro), named: "people.selected.dark.ios")
    }
    #endif
}
