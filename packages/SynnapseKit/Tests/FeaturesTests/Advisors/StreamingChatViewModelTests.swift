import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func sampleAdvisor() -> Advisor {
    Advisor(
        id: "financial",
        name: "Wealth Coach",
        specialty: "Budgets & cash flow",
        avatarColorHex: "#34d399",
        avatarInitials: "WC",
        unreadCount: 0
    )
}

@MainActor
@Suite("AdvisorsListViewModel")
struct AdvisorsListViewModelTests {

    @Test func startsIdleAndPopulatesOnRefresh() async {
        let api = MockAdvisorsAPI()
        await api.setListResponse([
            sampleAdvisor(),
            Advisor(
                id: "grant", name: "Grant Advisor", specialty: "NSF",
                avatarColorHex: "#60a5fa", avatarInitials: "GA"
            )
        ])
        let vm = AdvisorsListViewModel(api: api)
        if case .idle = vm.state {} else {
            Issue.record("expected idle initial state")
        }
        await vm.refresh()
        if case .ready(let advisors) = vm.state {
            #expect(advisors.count == 2)
        } else {
            Issue.record("expected ready, got \(vm.state)")
        }
        // First advisor auto-selected.
        #expect(vm.selectedAdvisorId == "financial")
        #expect(vm.selectedAdvisor?.name == "Wealth Coach")
    }

    @Test func errorStateIsExposedOnAPIFailure() async {
        let api = MockAdvisorsAPI()
        await api.setListError(APIError.server(status: 502))
        let vm = AdvisorsListViewModel(api: api)
        await vm.refresh()
        if case .error = vm.state {} else {
            Issue.record("expected error, got \(vm.state)")
        }
    }

    @Test func chatViewModelInheritsAdvisorAndLastThread() async {
        let api = MockAdvisorsAPI()
        let advisor = Advisor(
            id: "wealth", name: "W", specialty: "S",
            avatarColorHex: "#fff", avatarInitials: "W",
            lastThreadId: "thr_xyz"
        )
        let listVM = AdvisorsListViewModel(api: api)
        let chatVM = listVM.chatViewModel(for: advisor)
        #expect(chatVM.advisor.id == "wealth")
        #expect(chatVM.threadId == "thr_xyz")
    }
}

@MainActor
@Suite("StreamingChatViewModel")
struct StreamingChatViewModelTests {

    @Test func sendBuffersComposerAndAppendsUserMessage() async {
        let api = MockAdvisorsAPI()
        await api.setStream([
            .text("Hi"),
            .text(", there"),
            .done(threadId: "thr_new")
        ])
        let vm = StreamingChatViewModel(api: api, advisor: sampleAdvisor())
        vm.composer = "hello"
        await vm.send()
        // After send(), composer is cleared and the user message is in
        // the array. The stream task races on a Task; pump until it
        // settles.
        try? await waitFor(timeout: .seconds(1)) {
            await !vm.isStreaming
        }
        #expect(vm.composer == "")
        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "hello")
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].content == "Hi, there")
        #expect(vm.messages[1].isStreaming == false)
        #expect(vm.threadId == "thr_new")
        #expect(vm.isStreaming == false)
    }

    @Test func emptyComposerIsIgnored() async {
        let api = MockAdvisorsAPI()
        await api.setStream([.text("noop"), .done(threadId: nil)])
        let vm = StreamingChatViewModel(api: api, advisor: sampleAdvisor())
        vm.composer = "   \n   "
        await vm.send()
        // Mock should never have been called.
        let count = await api.streamCallCount
        #expect(count == 0)
        #expect(vm.messages.isEmpty)
    }

    @Test func cancelFinalizesInflightAssistantMessage() async {
        let api = MockAdvisorsAPI()
        await api.setStream([
            .text("partial"),
            .text(" reply"),
            .done(threadId: nil)
        ], perDeltaDelay: .milliseconds(100))
        let vm = StreamingChatViewModel(api: api, advisor: sampleAdvisor())
        vm.composer = "go"
        await vm.send()
        // Give the first delta time to land but cancel before the
        // stream completes.
        try? await Task.sleep(for: .milliseconds(50))
        vm.cancel()
        try? await waitFor(timeout: .seconds(1)) {
            await !vm.isStreaming
        }
        #expect(vm.isStreaming == false)
        // The trailing assistant message must not be left in a
        // streaming state, even though the stream was interrupted.
        if let last = vm.messages.last {
            #expect(last.isStreaming == false)
        } else {
            Issue.record("expected at least one message")
        }
    }

    @Test func streamErrorIsRecordedWithoutCrashingTheView() async {
        let api = MockAdvisorsAPI()
        await api.setStreamError(APIError.server(status: 500))
        let vm = StreamingChatViewModel(api: api, advisor: sampleAdvisor())
        vm.composer = "anything"
        await vm.send()
        try? await waitFor(timeout: .seconds(1)) {
            await !vm.isStreaming
        }
        #expect(vm.lastError != nil)
        #expect(vm.isStreaming == false)
        // The pending assistant message is still in the array; it's
        // finalized (not streaming) and may be empty.
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.isStreaming == false)
    }

    @Test func errorDeltaPaintsLastErrorAndStops() async {
        let api = MockAdvisorsAPI()
        await api.setStream([
            .text("warming up"),
            .error("rate limit")
        ])
        let vm = StreamingChatViewModel(api: api, advisor: sampleAdvisor())
        vm.composer = "go"
        await vm.send()
        try? await waitFor(timeout: .seconds(1)) {
            await !vm.isStreaming
        }
        #expect(vm.lastError == "rate limit")
        #expect(vm.isStreaming == false)
    }
}

/// Lightweight wait loop — polls the predicate until it returns `true` or
/// the timeout expires. Used in lieu of `withTaskCancellationHandler`
/// gymnastics for the streaming view model.
@MainActor
private func waitFor(timeout: Duration, predicate: @escaping () async -> Bool) async throws {
    let start = ContinuousClock().now
    while ContinuousClock().now - start < timeout {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
}
