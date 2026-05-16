import Foundation
import Models
import Networking

/// Concurrency-safe cache for the inbox surface. Mirrors the [[PeopleRepository]]
/// shape: actor, ETag-aware, 304 leaves the cache intact. Adds cursor-based
/// pagination on top.
public actor InboxRepository {
    private let api: InboxAPI
    public private(set) var items: [InboxItem] = []
    public private(set) var nextCursor: String?
    private var etag: String?
    private var sourceFilter: Source?

    public init(api: InboxAPI) {
        self.api = api
    }

    public func setSourceFilter(_ source: Source?) {
        sourceFilter = source
        items.removeAll()
        nextCursor = nil
        etag = nil
    }

    public func refresh() async throws {
        let response = try await api.list(
            cursor: nil,
            source: sourceFilter,
            ifNoneMatch: etag
        )
        if response.notModified {
            if let newETag = response.etag { etag = newETag }
            return
        }
        if let page = response.page {
            self.items = page.items
            self.nextCursor = page.nextCursor
        }
        if let newETag = response.etag { etag = newETag }
    }

    public func loadMore() async throws {
        guard let cursor = nextCursor else { return }
        let response = try await api.list(
            cursor: cursor,
            source: sourceFilter,
            ifNoneMatch: nil
        )
        if response.notModified { return }
        if let page = response.page {
            // Append, deduplicated by id (server may overlap pages by 1 row
            // on its boundary edge).
            var seen = Set(items.map(\.id))
            for item in page.items where !seen.contains(item.id) {
                items.append(item)
                seen.insert(item.id)
            }
            self.nextCursor = page.nextCursor
        }
    }

    public func snapshot() -> [InboxItem] { items }
}
