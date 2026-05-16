import Foundation
import Testing
@testable import Models
@testable import Features

private func makeItem(_ id: String) -> SpotlightItem {
    SpotlightItem(
        id: id,
        messageId: "m-\(id)",
        kind: "pick",
        issueLabel: "ISSUE",
        summary: id,
        runLink: nil,
        paperUrl: nil,
        overleafUrl: nil,
        status: "pending",
        detectedAt: Date(timeIntervalSince1970: 1_700_000_000),
        decidedAt: nil,
        message: .init(
            senderDisplay: "x",
            sender: "x@y",
            subject: "s",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: nil,
            threadId: nil
        )
    )
}

@Suite("SpotlightViewModel")
struct SpotlightViewModelTests {

    @Test @MainActor
    func debounceCollapsesRapidQueries() async throws {
        let mock = MockSpotlightAPI()
        await mock.setNextPage(SpotlightPage(events: [makeItem("a")], nextCursor: nil))
        let vm = SpotlightViewModel(api: mock, debounce: .milliseconds(80))

        vm.setQuery("m")
        vm.setQuery("mu")
        vm.setQuery("mut")
        vm.setQuery("muta")
        try await Task.sleep(for: .milliseconds(250))
        let calls = await mock.callCount
        // One initial idle-state load is allowed; the debounce should collapse
        // the four rapid query mutations into at most one extra fetch.
        #expect(calls <= 2)
    }

    @Test @MainActor
    func staleFetchIsCancelledWhenNewQueryArrives() async throws {
        let mock = MockSpotlightAPI()
        await mock.setDelay(.milliseconds(150))
        await mock.setNextPage(SpotlightPage(events: [makeItem("late")], nextCursor: nil))
        let vm = SpotlightViewModel(api: mock, debounce: .milliseconds(10))

        vm.setQuery("first")
        try await Task.sleep(for: .milliseconds(40))
        await mock.setNextPage(SpotlightPage(events: [makeItem("second")], nextCursor: nil))
        vm.setQuery("second")
        try await Task.sleep(for: .milliseconds(400))

        switch vm.state {
        case .results(let items):
            #expect(items.map(\.id) == ["second"])
        default:
            Issue.record("expected results state, got \(vm.state)")
        }
    }

    @Test @MainActor
    func emptyAndErrorAreDistinctStates() async throws {
        let mock = MockSpotlightAPI()
        await mock.setNextPage(SpotlightPage(events: [], nextCursor: nil))
        let vm = SpotlightViewModel(api: mock, debounce: .milliseconds(10))
        await vm.refresh()
        if case .empty = vm.state {} else { Issue.record("expected empty, got \(vm.state)") }

        await mock.setNextError(URLError(.notConnectedToInternet))
        await vm.refresh()
        if case .error = vm.state {} else { Issue.record("expected error, got \(vm.state)") }
    }

    @Test @MainActor
    func selectingItemExposesIt() async throws {
        let mock = MockSpotlightAPI()
        let item = makeItem("pick-me")
        await mock.setNextPage(SpotlightPage(events: [item], nextCursor: nil))
        let vm = SpotlightViewModel(api: mock, debounce: .milliseconds(10))
        await vm.refresh()
        vm.select(item)
        #expect(vm.selected?.id == "pick-me")
    }

    @Test
    func viewModelIsMainActor() async throws {
        // Compile-time: building it off-main must require an await hop.
        let mock = MockSpotlightAPI()
        let vm = await MainActor.run { SpotlightViewModel(api: mock) }
        let id = await MainActor.run { vm.query }
        #expect(id.isEmpty)
    }
}
