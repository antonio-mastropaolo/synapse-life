import Foundation
import Models

/// Holds the spotlight page cache, the current pagination cursor, and the
/// last seen ETag. Concurrency-safe by virtue of being an actor; views read
/// snapshots via the `@MainActor` view model.
public actor SpotlightRepository {
    private let api: SpotlightAPI
    private let scope: SpotlightScope?
    private(set) public var items: [SpotlightItem] = []
    private var cursor: String?
    private var etag: String?
    private var reachedEnd: Bool = false

    public init(api: SpotlightAPI, scope: SpotlightScope? = nil) {
        self.api = api
        self.scope = scope
    }

    /// Discard the cursor + cached items and fetch from scratch. Honors any
    /// previously-seen ETag — a 304 keeps the existing cache and returns
    /// quietly.
    public func refresh() async throws {
        let response = try await api.list(scope: scope, cursor: nil, ifNoneMatch: etag)
        if response.notModified {
            // Server confirmed the cache is current — leave items alone.
            if let newETag = response.etag { etag = newETag }
            return
        }
        guard let page = response.page else { return }
        items = page.events
        cursor = page.nextCursor
        reachedEnd = page.nextCursor == nil
        if let newETag = response.etag { etag = newETag }
    }

    public func loadMore() async throws {
        if reachedEnd { return }
        guard let nextCursor = cursor else {
            reachedEnd = true
            return
        }
        let response = try await api.list(scope: scope, cursor: nextCursor, ifNoneMatch: nil)
        guard let page = response.page else { return }
        items.append(contentsOf: page.events)
        cursor = page.nextCursor
        reachedEnd = page.nextCursor == nil
    }

    public func clear() {
        items = []
        cursor = nil
        etag = nil
        reachedEnd = false
    }
}
