import Foundation
import Testing
@testable import Models
@testable import Features

@MainActor
@Suite("CommandBarViewModel")
struct CommandBarViewModelTests {

    private func makeVM(askDelayNanos: UInt64 = 18_000_000) -> CommandBarViewModel {
        CommandBarViewModel(
            askAPI: LocalStubAskAPI(interTokenDelayNanos: askDelayNanos),
            advisorIds: ["financial", "tax"],
            contextProvider: { AskContext(accounts: [], recentTransactions: []) }
        )
    }

    @Test func emptyQueryShowsTopSurfaces() {
        let vm = makeVM()
        #expect(!vm.suggestions.isEmpty)
        // At least one suggestion should be a surface jump.
        let surfaceSugg = vm.suggestions.first { suggestion in
            if case .surface = suggestion.kind { return true }
            return false
        }
        #expect(surfaceSugg != nil)
    }

    @Test func queryFiltersToMatchingSurfaces() {
        let vm = makeVM()
        vm.query = "trans"
        let labels = vm.suggestions.map(\.label)
        #expect(labels.contains(where: { $0.contains("Transactions") }))
    }

    @Test func askQueryIncludesAdvisorChips() {
        let vm = makeVM()
        vm.query = "ask"
        let hasAdvisor = vm.suggestions.contains { sugg in
            if case .askAdvisor = sugg.kind { return true }
            return false
        }
        #expect(hasAdvisor)
    }

    @Test func submitStartsStreamingAndProducesAnswer() async throws {
        let vm = makeVM(askDelayNanos: 0)
        vm.query = "what is my net worth"
        vm.submit()
        await vm.activeTask?.value
        #expect(!vm.streamingAnswer.isEmpty)
        #expect(vm.isStreaming == false)
    }

    @Test func applyStoresLastDispatched() {
        let vm = makeVM()
        let sugg = CommandSuggestion(
            id: "surface.transactions",
            kind: .surface(.transactions),
            label: "Open Transactions"
        )
        vm.apply(sugg)
        #expect(vm.lastDispatched?.id == "surface.transactions")
    }

    @Test func suggestionsCappedAtFive() {
        let vm = makeVM()
        vm.query = ""
        #expect(vm.suggestions.count <= 5)
    }
}
