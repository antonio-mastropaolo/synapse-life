import Foundation
import Observation
import Models
import Networking

public enum InboxState: Sendable, Equatable {
    case idle
    case loading
    case results([InboxItem])
    case empty
    case error(String)
}

/// View model for the Inbox surface. Holds the message list, current
/// folder filter, unread count projection, and the optimistic mark-read
/// flow (with rollback on server failure).
///
/// Read-only in M7: no compose, no reply, no send. The only mutation is
/// the local read flag.
@MainActor
@Observable
public final class InboxListViewModel {

    public private(set) var state: InboxState = .idle
    public private(set) var items: [InboxItem] = []
    public private(set) var nextCursor: String?
    public var selected: InboxItem?
    public private(set) var folder: SourceFolder?
    public private(set) var lastError: String?

    private let api: InboxAPI
    private var fetchTask: Task<Void, Never>?

    public init(api: InboxAPI) {
        self.api = api
    }

    public var unreadCount: Int {
        items.lazy.filter { !$0.isRead }.count
    }

    public var visibleItems: [InboxItem] {
        guard let folder else { return items }
        return items.filter { $0.source == folder.source }
    }

    public func refresh() async {
        fetchTask?.cancel()
        await runFetch()
    }

    public func loadMore() async {
        guard let cursor = nextCursor else { return }
        do {
            let response = try await api.list(
                cursor: cursor,
                source: folder?.source,
                ifNoneMatch: nil
            )
            if let page = response.page {
                var seen = Set(items.map(\.id))
                for item in page.items where !seen.contains(item.id) {
                    items.append(item)
                    seen.insert(item.id)
                }
                self.nextCursor = page.nextCursor
                state = items.isEmpty ? .empty : .results(items)
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    public func select(_ item: InboxItem) {
        selected = item
        // Browsing the message implicitly marks it read.
        if !item.isRead {
            Task { await markRead(id: item.id) }
        }
    }

    public func clearSelection() {
        selected = nil
    }

    public func selectFolder(_ folder: SourceFolder?) {
        self.folder = folder
    }

    /// Optimistically flip the read flag locally, then POST to the server.
    /// If the server fails, roll the flag back and surface the error.
    public func markRead(id: String) async {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let priorIsRead = items[idx].isRead
        items[idx].isRead = true
        if let sel = selected, sel.id == id {
            selected?.isRead = true
        }
        // Re-emit state so observers see the flip without waiting for the
        // network round trip.
        state = .results(items)
        do {
            try await api.markRead(id: id, read: true)
        } catch {
            // Roll back.
            if let rollbackIdx = items.firstIndex(where: { $0.id == id }) {
                items[rollbackIdx].isRead = priorIsRead
                if let sel = selected, sel.id == id {
                    selected?.isRead = priorIsRead
                }
                state = .results(items)
            }
            lastError = String(describing: error)
        }
    }

    /// Deterministic state for snapshot tests / previews.
    public func injectForSnapshots(state: InboxState, items: [InboxItem]) {
        self.state = state
        self.items = items
    }

    private func runFetch() async {
        state = .loading
        do {
            let response = try await api.list(
                cursor: nil,
                source: folder?.source,
                ifNoneMatch: nil
            )
            if Task.isCancelled { return }
            if let page = response.page {
                self.items = page.items
                self.nextCursor = page.nextCursor
            }
            state = items.isEmpty ? .empty : .results(items)
        } catch is CancellationError {
            return
        } catch {
            state = .error(String(describing: error))
        }
    }
}
