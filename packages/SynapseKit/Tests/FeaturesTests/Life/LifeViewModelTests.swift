import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features
@testable import DesignSystem

@MainActor
@Suite("LifeViewModel")
struct LifeViewModelTests {

    private func sample(_ id: String, _ t: TimeInterval) -> LifeEntry {
        LifeEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: t),
            kind: .transaction,
            text: "row \(id)"
        )
    }

    @Test
    func startsIdleAndTransitionsToReadyOnRefresh() async {
        let api = MockLifeAPI()
        await api.setEntries([sample("a", 1_747_407_600)])
        let vm = LifeViewModel(api: api)
        if case .idle = vm.state {} else {
            Issue.record("expected idle initial state")
        }
        await vm.refresh()
        if case .ready(let entries) = vm.state {
            #expect(entries.count == 1)
            #expect(entries[0].id == "a")
        } else {
            Issue.record("expected ready, got \(vm.state)")
        }
    }

    @Test
    func errorStateIsExposedOnAPIFailure() async {
        let api = MockLifeAPI()
        await api.setNextError(APIError.server(status: 500))
        let vm = LifeViewModel(api: api)
        await vm.refresh()
        if case .error = vm.state {} else {
            Issue.record("expected error, got \(vm.state)")
        }
    }

    @Test
    func appendConcatenatesEntriesWhenReady() async {
        let api = MockLifeAPI()
        await api.setEntries([sample("a", 1_747_407_600)])
        let vm = LifeViewModel(api: api)
        await vm.refresh()
        vm.append([sample("b", 1_747_407_660), sample("c", 1_747_407_720)])
        if case .ready(let entries) = vm.state {
            #expect(entries.map(\.id) == ["a", "b", "c"])
        } else {
            Issue.record("expected ready after append")
        }
    }

    @Test
    func appendFromIdleSeedsBuffer() {
        let vm = LifeViewModel(api: MockLifeAPI())
        vm.append([sample("a", 1_747_407_600)])
        if case .ready(let entries) = vm.state {
            #expect(entries.count == 1)
        } else {
            Issue.record("expected ready after seeding append")
        }
    }

    @Test
    func anchoredToTailDefaultsTrue() {
        let vm = LifeViewModel(api: MockLifeAPI())
        #expect(vm.anchoredToTail == true)
        vm.anchoredToTail = false
        #expect(vm.anchoredToTail == false)
    }

    @Test
    func updateRenderPathPicksShaderByDefault() {
        let vm = LifeViewModel(api: MockLifeAPI())
        vm.updateRenderPath(accessibility: LifeAccessibilityEnvironment())
        #expect(vm.currentRenderPath == .shader)
    }
}
