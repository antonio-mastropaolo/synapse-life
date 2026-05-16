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

/// Snapshot references for the M9 Sequences surfaces. 8 refs:
///   - macOS list + macOS editor × {light, dark}
///   - iOS list + iOS editor × {light, dark}
@Suite("SequencesScreenSnapshot")
@MainActor
struct SequencesScreenSnapshotTests {

    private func sampleSequences() -> [Sequence] {
        let now = Date().timeIntervalSince1970
        let r1 = ServerSequenceRow(
            id: "seq-a", opportunity_id: "opp-a",
            lead_email: "lead.a@example.com", lead_display: "Alice Wong",
            subject: "Quick question on the editorial dashboard",
            touch1_body: "Hi Alice — saw your post on dashboards. Curious if you've already evaluated similar tools.",
            current_touch: 1,
            last_sent_at: now - 86_400 * 2,
            next_due_at: now + 86_400 * 1,
            status: "active",
            last_log: nil,
            created_at: now - 86_400 * 3
        )
        let r2 = ServerSequenceRow(
            id: "seq-b", opportunity_id: "opp-b",
            lead_email: "lead.b@example.com", lead_display: "Bao Tran",
            subject: "Re: pricing for an annotation pilot",
            touch1_body: "Hi Bao — picking up the thread on pricing. Are you still working from the same brief?",
            current_touch: 2,
            last_sent_at: now - 86_400 * 6,
            next_due_at: now - 3600 * 4,
            status: "paused",
            last_log: "paused by operator",
            created_at: now - 86_400 * 10
        )
        let r3 = ServerSequenceRow(
            id: "seq-c", opportunity_id: "opp-c",
            lead_email: "lead.c@example.com", lead_display: "Carla Mendes",
            subject: "Follow-up: design review feedback",
            touch1_body: "Hi Carla — I'm sending you the consolidated notes from the design review.",
            current_touch: 3,
            last_sent_at: now - 86_400 * 14,
            next_due_at: nil,
            status: "replied",
            last_log: "received reply, paused",
            created_at: now - 86_400 * 20
        )
        return [r1, r2, r3].map(Sequence.fromServerRow)
    }

    private func listViewModel() -> SequencesViewModel {
        let mock = MockSequencesAPI()
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        vm.injectForSnapshots(state: .results(sampleSequences()), selected: nil)
        return vm
    }

    private func editorViewModel() -> SequencesViewModel {
        let mock = MockSequencesAPI()
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        let sequences = sampleSequences()
        vm.injectForSnapshots(state: .results(sequences), selected: sequences[0])
        return vm
    }

    #if os(macOS)
    private func hostMac(_ view: some View, scheme: ColorScheme, width: CGFloat = 1100, height: CGFloat = 640) -> NSView {
        let host = NSHostingView(rootView: AnyView(
            view
                .frame(width: width, height: height)
                .environment(\.colorScheme, scheme)
                .identity(.editorial)
        ))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test func listLightMac() throws {
        let view = SequencesView(viewModel: listViewModel())
        assertSnapshot(of: hostMac(view, scheme: .light), as: .image,
                       named: "sequences.list.light.mac")
    }

    @Test func listDarkMac() throws {
        let view = SequencesView(viewModel: listViewModel())
        assertSnapshot(of: hostMac(view, scheme: .dark), as: .image,
                       named: "sequences.list.dark.mac")
    }

    @Test func editorLightMac() throws {
        let vm = editorViewModel()
        guard let seq = vm.selected else { Issue.record("no selection"); return }
        let view = SequenceStageEditor(viewModel: vm, sequence: seq)
        assertSnapshot(of: hostMac(view, scheme: .light, width: 720, height: 640), as: .image,
                       named: "sequences.editor.light.mac")
    }

    @Test func editorDarkMac() throws {
        let vm = editorViewModel()
        guard let seq = vm.selected else { Issue.record("no selection"); return }
        let view = SequenceStageEditor(viewModel: vm, sequence: seq)
        assertSnapshot(of: hostMac(view, scheme: .dark, width: 720, height: 640), as: .image,
                       named: "sequences.editor.dark.mac")
    }
    #endif

    #if os(iOS)
    private func hostIOS(_ view: some View, scheme: ColorScheme, height: CGFloat = 874) -> UIViewController {
        let host = UIHostingController(rootView: AnyView(
            view
                .environment(\.colorScheme, scheme)
                .identity(.editorial)
        ))
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: height)
        host.view.layoutIfNeeded()
        return host
    }

    @Test func listLightIOS() throws {
        let view = SequencesView(viewModel: listViewModel())
        assertSnapshot(of: hostIOS(view, scheme: .light),
                       as: .image(on: .iPhone13Pro),
                       named: "sequences.list.light.ios")
    }

    @Test func listDarkIOS() throws {
        let view = SequencesView(viewModel: listViewModel())
        assertSnapshot(of: hostIOS(view, scheme: .dark),
                       as: .image(on: .iPhone13Pro),
                       named: "sequences.list.dark.ios")
    }

    @Test func editorLightIOS() throws {
        let vm = editorViewModel()
        guard let seq = vm.selected else { Issue.record("no selection"); return }
        let view = SequenceStageEditor(viewModel: vm, sequence: seq)
        assertSnapshot(of: hostIOS(view, scheme: .light),
                       as: .image(on: .iPhone13Pro),
                       named: "sequences.editor.light.ios")
    }

    @Test func editorDarkIOS() throws {
        let vm = editorViewModel()
        guard let seq = vm.selected else { Issue.record("no selection"); return }
        let view = SequenceStageEditor(viewModel: vm, sequence: seq)
        assertSnapshot(of: hostIOS(view, scheme: .dark),
                       as: .image(on: .iPhone13Pro),
                       named: "sequences.editor.dark.ios")
    }
    #endif
}
