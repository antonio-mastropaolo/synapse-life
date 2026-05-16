import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func sampleSequence(id: String = "seq-1", currentTouch: Int = 1) -> Sequence {
    let row = ServerSequenceRow(
        id: id,
        opportunity_id: "opp-\(id)",
        lead_email: "\(id)@example.com",
        lead_display: id.uppercased(),
        subject: "Subject \(id)",
        touch1_body: "Body \(id)",
        current_touch: currentTouch,
        last_sent_at: 1_739_625_600,
        next_due_at: 1_739_712_000,
        status: "active",
        last_log: nil,
        created_at: 1_739_625_500
    )
    return Sequence.fromServerRow(row)
}

@Suite("SequencesViewModel — list")
@MainActor
struct SequencesViewModelListTests {

    @Test
    func refreshPopulatesResults() async {
        let mock = MockSequencesAPI()
        await mock.setNextList([sampleSequence(id: "a"), sampleSequence(id: "b")])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        if case .results(let rows) = vm.state {
            #expect(rows.count == 2)
        } else {
            Issue.record("expected .results, got \(vm.state)")
        }
    }

    @Test
    func refreshGoesEmptyWhenServerReturnsNoRows() async {
        let mock = MockSequencesAPI()
        await mock.setNextList([])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        #expect(vm.state == .empty)
    }

    @Test
    func statusFilterChangeTriggersRefresh() async {
        let mock = MockSequencesAPI()
        await mock.setNextList([sampleSequence(id: "a")])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        #expect(await mock.listCallCount == 1)
        await vm.setStatusFilter(.paused)
        #expect(await mock.listCallCount == 2)
        #expect(vm.statusFilter == .paused)
    }

    @Test
    func statusFilterUnchangedDoesNotRefetch() async {
        let mock = MockSequencesAPI()
        await mock.setNextList([sampleSequence(id: "a")])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        await vm.setStatusFilter(.active) // already active
        #expect(await mock.listCallCount == 1)
    }

    @Test
    func errorStateExposesDescription() async {
        struct Boom: Error {}
        let mock = MockSequencesAPI()
        await mock.setNextError(Boom())
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        if case .error = vm.state {
            // expected
        } else {
            Issue.record("expected .error, got \(vm.state)")
        }
    }

    @Test
    func notModifiedKeepsExistingResults() async {
        let mock = MockSequencesAPI()
        await mock.setNextList([sampleSequence(id: "a")], etag: "\"v1\"")
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        guard case .results(let firstRows) = vm.state else {
            Issue.record("expected .results"); return
        }

        await mock.setNotModified(etag: "\"v1\"")
        await vm.refresh()
        if case .results(let rows) = vm.state {
            #expect(rows.map(\.id) == firstRows.map(\.id))
        } else {
            Issue.record("expected .results after 304, got \(vm.state)")
        }
    }
}

@Suite("SequencesViewModel — selection and stages")
@MainActor
struct SequencesViewModelSelectionTests {

    @Test
    func selectSeedsActiveStageAndDraftBuffers() async {
        let mock = MockSequencesAPI()
        let seq = sampleSequence(id: "a", currentTouch: 1)
        await mock.setNextList([seq])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        vm.select(seq)
        #expect(vm.selected?.id == seq.id)
        #expect(vm.selectedStageId == seq.activeStage?.id)
        #expect(vm.draftSubject(forStage: seq.stages[0].id) == seq.stages[0].subject)
        #expect(vm.draftBody(forStage: seq.stages[0].id) == seq.stages[0].body)
    }

    @Test
    func selectStageOverridesActiveStage() async {
        let mock = MockSequencesAPI()
        let seq = sampleSequence(id: "a", currentTouch: 1)
        await mock.setNextList([seq])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        vm.select(seq)
        vm.selectStage(id: seq.stages[1].id)
        #expect(vm.selectedStageId == seq.stages[1].id)
    }
}

@Suite("SequencesViewModel — autosave")
@MainActor
struct SequencesViewModelAutosaveTests {

    @Test
    func debouncedEditEventuallyPersists() async {
        let mock = MockSequencesAPI()
        let seq = sampleSequence(id: "a")
        await mock.setNextList([seq])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(20))
        await vm.refresh()
        vm.select(seq)
        let stageId = seq.stages[1].id

        vm.updateDraftSubject(stageId: stageId, value: "Follow-up draft")
        #expect(vm.draftSaveState(forStage: stageId) == .dirty)

        await vm.flushPendingSave(stageId: stageId)

        #expect(vm.draftSaveState(forStage: stageId) == .saved)
        #expect(await mock.upsertCallCount == 1)
        let delta = await mock.lastUpsertDelta
        #expect(delta?.stageId == stageId)
        #expect(delta?.subject == "Follow-up draft")
    }

    @Test
    func rapidTypingCollapsesIntoOneSave() async {
        let mock = MockSequencesAPI()
        let seq = sampleSequence(id: "a")
        await mock.setNextList([seq])
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(40))
        await vm.refresh()
        vm.select(seq)
        let stageId = seq.stages[1].id

        // Three rapid edits within a single debounce window.
        vm.updateDraftBody(stageId: stageId, value: "H")
        vm.updateDraftBody(stageId: stageId, value: "Hi")
        vm.updateDraftBody(stageId: stageId, value: "Hi there.")

        await vm.flushPendingSave(stageId: stageId)
        #expect(await mock.upsertCallCount == 1)
        let last = await mock.lastUpsertDelta
        #expect(last?.body == "Hi there.")
    }

    @Test
    func failedSaveSurfacesState() async {
        struct Boom: Error {}
        let mock = MockSequencesAPI()
        let seq = sampleSequence(id: "a")
        await mock.setNextList([seq])
        await mock.setUpsertError(Boom())
        let vm = SequencesViewModel(api: mock, autosaveDebounce: .milliseconds(10))
        await vm.refresh()
        vm.select(seq)
        let stageId = seq.stages[1].id

        vm.updateDraftSubject(stageId: stageId, value: "Will fail")
        await vm.flushPendingSave(stageId: stageId)
        if case .failed = vm.draftSaveState(forStage: stageId) {
            // expected
        } else {
            Issue.record("expected .failed, got \(vm.draftSaveState(forStage: stageId))")
        }
    }
}
