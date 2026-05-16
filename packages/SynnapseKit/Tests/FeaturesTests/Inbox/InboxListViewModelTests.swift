import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

/// State-machine tests for [[InboxListViewModel]]. Inbox is READ-ONLY in M7;
/// the only mutation supported here is optimistic mark-read with rollback on
/// server failure. No compose / reply / send.
@Suite("InboxListViewModel")
@MainActor
struct InboxListViewModelTests {

    private func sampleItems(unread: Int, read: Int = 0) -> [InboxItem] {
        var rows: [InboxItem] = []
        for i in 0..<unread {
            rows.append(InboxItem(
                id: "u-\(i)", source: .gmail, threadId: nil,
                sender: "u\(i)@x.io", senderDisplay: "U \(i)",
                subject: "Unread \(i)", body: "Body \(i)",
                bodyPreview: "Body \(i)",
                receivedAt: Date(timeIntervalSince1970: TimeInterval(1_730_000_000 - i)),
                isRead: false
            ))
        }
        for i in 0..<read {
            rows.append(InboxItem(
                id: "r-\(i)", source: .gmail, threadId: nil,
                sender: "r\(i)@x.io", senderDisplay: "R \(i)",
                subject: "Read \(i)", body: "Body",
                bodyPreview: "Body",
                receivedAt: Date(timeIntervalSince1970: TimeInterval(1_725_000_000 - i)),
                isRead: true
            ))
        }
        return rows
    }

    @Test
    func refreshTransitionsAndPopulatesUnreadCount() async {
        let mock = MockInboxAPI()
        await mock.setNextItems(sampleItems(unread: 3, read: 2))
        let vm = InboxListViewModel(api: mock)
        await vm.refresh()
        if case .results(let rows) = vm.state {
            #expect(rows.count == 5)
        } else {
            Issue.record("expected .results, got \(vm.state)")
        }
        #expect(vm.unreadCount == 3)
    }

    @Test
    func emptyServerProducesEmptyState() async {
        let mock = MockInboxAPI()
        await mock.setNextItems([])
        let vm = InboxListViewModel(api: mock)
        await vm.refresh()
        #expect(vm.state == .empty)
        #expect(vm.unreadCount == 0)
    }

    @Test
    func loadMoreAppendsToExistingList() async {
        let mock = MockInboxAPI()
        await mock.setNextItems(sampleItems(unread: 2))
        // Stage the first page WITH hasMore so a nextCursor lands.
        await mock.setNextHasMore(true)
        let vm = InboxListViewModel(api: mock)
        await vm.refresh()
        #expect(vm.items.count == 2)
        #expect(vm.nextCursor != nil)

        // Stage the next page — final page, hasMore=false.
        let nextPage = [
            InboxItem(
                id: "next-1", source: .gmail, threadId: nil,
                sender: "n@x.io", senderDisplay: "N",
                subject: "Next 1", body: "...", bodyPreview: "...",
                receivedAt: Date(timeIntervalSince1970: 1_720_000_000),
                isRead: false
            )
        ]
        await mock.setNextItems(nextPage)
        await mock.setNextHasMore(false)
        await vm.loadMore()
        #expect(vm.items.count == 3)
        #expect(vm.items.last?.id == "next-1")
    }

    @Test
    func optimisticMarkReadFlipsImmediately() async {
        let mock = MockInboxAPI()
        await mock.setNextItems(sampleItems(unread: 2))
        let vm = InboxListViewModel(api: mock)
        await vm.refresh()
        #expect(vm.unreadCount == 2)
        // Mark-read is optimistic: the count drops BEFORE the server replies.
        let task = Task { await vm.markRead(id: "u-0") }
        // Give the @MainActor a chance to apply the optimistic mutation.
        await Task.yield()
        #expect(vm.unreadCount == 1)
        #expect(vm.items.first { $0.id == "u-0" }?.isRead == true)
        await task.value
    }

    @Test
    func optimisticMarkReadRollsBackOnServerFailure() async {
        struct E: Error {}
        let mock = MockInboxAPI()
        await mock.setNextItems(sampleItems(unread: 2))
        await mock.setNextMarkReadError(E())
        let vm = InboxListViewModel(api: mock)
        await vm.refresh()
        await vm.markRead(id: "u-0")
        // Server said no — count and flag must roll back.
        #expect(vm.unreadCount == 2)
        #expect(vm.items.first { $0.id == "u-0" }?.isRead == false)
        // And surface the failure once.
        #expect(vm.lastError != nil)
    }

    @Test
    func selectionRoundTripsAndClears() async {
        let mock = MockInboxAPI()
        let items = sampleItems(unread: 2)
        await mock.setNextItems(items)
        let vm = InboxListViewModel(api: mock)
        await vm.refresh()
        vm.select(items[0])
        #expect(vm.selected?.id == "u-0")
        vm.clearSelection()
        #expect(vm.selected == nil)
    }

    @Test
    func injectForSnapshotsForcesDeterministicState() async {
        let mock = MockInboxAPI()
        let vm = InboxListViewModel(api: mock)
        let items = sampleItems(unread: 3, read: 1)
        vm.injectForSnapshots(state: .results(items), items: items)
        if case .results(let rows) = vm.state {
            #expect(rows.count == 4)
        } else {
            Issue.record("expected .results")
        }
        #expect(vm.unreadCount == 3)
    }

    @Test
    func folderFilterScopesByMessageSource() async {
        let mock = MockInboxAPI()
        var items = sampleItems(unread: 2)
        items.append(InboxItem(
            id: "o-1", source: .outlook, threadId: nil,
            sender: "x@x.io", senderDisplay: "X",
            subject: "O", body: "...", bodyPreview: "...",
            receivedAt: Date(), isRead: false
        ))
        await mock.setNextItems(items)
        let vm = InboxListViewModel(api: mock)
        await vm.refresh()
        vm.selectFolder(.gmail)
        #expect(vm.visibleItems.allSatisfy { $0.source == .gmail })
        vm.selectFolder(nil)
        #expect(vm.visibleItems.count == 3)
    }
}
