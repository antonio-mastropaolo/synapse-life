import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

/// State-machine tests for [[PeopleViewModel]]. Covers: refresh transitions,
/// search debounce, selection lifecycle, error surface.
@Suite("PeopleViewModel")
@MainActor
struct PeopleViewModelTests {

    private func samplePeople() -> [Person] {
        [
            Person(
                identity: "amastropaolo@wm.edu",
                displayName: "Antonio Mastropáolo",
                importanceWeight: 0.9, autoBoost: 0.0, effectiveWeight: 0.9,
                blacklisted: false, notes: nil,
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
                totalMessages: 38, firstSeen: nil, lastSeen: nil,
                distinctThreads: 12, awaitingMyReply: 0, openActions: 2,
                sources: [.gmail], avgImportance: 0.55,
                avatarURL: nil, avatarStatus: nil, kind: .person
            )
        ]
    }

    @Test
    func refreshTransitionsIdleLoadingResults() async {
        let mock = MockPeopleAPI()
        await mock.setNextPeople(samplePeople())
        let vm = PeopleViewModel(api: mock)
        #expect(vm.state == .idle)
        await vm.refresh()
        if case .results(let rows) = vm.state {
            #expect(rows.count == 2)
        } else {
            Issue.record("expected .results, got \(vm.state)")
        }
    }

    @Test
    func refreshWithEmptyServerProducesEmptyState() async {
        let mock = MockPeopleAPI()
        await mock.setNextPeople([])
        let vm = PeopleViewModel(api: mock)
        await vm.refresh()
        #expect(vm.state == .empty)
    }

    @Test
    func refreshErrorTransitionsToErrorState() async {
        struct E: Error {}
        let mock = MockPeopleAPI()
        await mock.setNextError(E())
        let vm = PeopleViewModel(api: mock)
        await vm.refresh()
        if case .error = vm.state {} else {
            Issue.record("expected .error, got \(vm.state)")
        }
    }

    @Test
    func searchFiltersByDiacriticInsensitiveLastName() async {
        let mock = MockPeopleAPI()
        await mock.setNextPeople(samplePeople())
        let vm = PeopleViewModel(api: mock)
        await vm.refresh()
        let filtered = vm.applySearch("mastropaolo")
        #expect(filtered.count == 1)
        #expect(filtered.first?.identity == "amastropaolo@wm.edu")
    }

    @Test
    func selectionRoundTripsAndClears() async {
        let mock = MockPeopleAPI()
        await mock.setNextPeople(samplePeople())
        let vm = PeopleViewModel(api: mock)
        await vm.refresh()
        let target = samplePeople()[0]
        vm.select(target)
        #expect(vm.selected?.identity == target.identity)
        vm.clearSelection()
        #expect(vm.selected == nil)
    }

    @Test
    func searchDebouncesIntoSingleFinalApplication() async {
        // The view model exposes a debounced search seam that callers (the
        // searchable view binding) hit on every keystroke. After the
        // debounce window passes, only the final query should be reflected
        // in the visible filter.
        let mock = MockPeopleAPI()
        await mock.setNextPeople(samplePeople())
        let vm = PeopleViewModel(api: mock, debounce: .milliseconds(20))
        await vm.refresh()

        // Push a burst of queries; only the last should "land".
        vm.queueSearch("antoni")
        vm.queueSearch("antoni")
        vm.queueSearch("mastropaolo")
        // Wait past the debounce window.
        try? await Task.sleep(for: .milliseconds(80))
        let visible = vm.visiblePeople
        #expect(visible.count == 1)
        #expect(visible.first?.identity == "amastropaolo@wm.edu")
    }

    @Test
    func injectForSnapshotsForcesDeterministicState() async {
        let mock = MockPeopleAPI()
        let vm = PeopleViewModel(api: mock)
        let people = samplePeople()
        vm.injectForSnapshots(state: .results(people), people: people)
        if case .results(let rows) = vm.state {
            #expect(rows.count == 2)
        } else {
            Issue.record("expected .results after injection")
        }
    }
}
