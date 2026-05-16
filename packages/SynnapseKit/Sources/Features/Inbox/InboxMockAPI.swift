import Foundation
import Models
import Networking

/// Test + preview double for the Inbox surface. Lives in `Features` for the
/// same reason as [[MockPeopleAPI]] — SnapshotTests-visibility.
public actor MockInboxAPI: InboxAPI {
    public private(set) var callCount: Int = 0
    public private(set) var lastCursor: String?
    public private(set) var lastSource: Source?
    public private(set) var lastIfNoneMatch: String?
    public private(set) var markReadCalls: [(id: String, read: Bool)] = []

    private var nextItems: [InboxItem] = []
    private var nextEtag: String?
    private var nextNotModified: Bool = false
    private var nextHasMore: Bool = false
    private var nextError: Error?
    private var nextMarkReadError: Error?

    public init() {}

    public func setNextItems(_ items: [InboxItem], etag: String? = nil) {
        nextItems = items
        nextEtag = etag
        nextError = nil
        nextNotModified = false
    }

    public func setNotModified(etag: String?) {
        nextNotModified = true
        nextEtag = etag
        nextError = nil
    }

    public func setNextHasMore(_ has: Bool) {
        nextHasMore = has
    }

    public func setNextError(_ error: Error) {
        nextError = error
    }

    public func setNextMarkReadError(_ error: Error) {
        nextMarkReadError = error
    }

    public func list(
        cursor: String?,
        source: Source?,
        ifNoneMatch: String?
    ) async throws -> InboxResponse {
        callCount += 1
        lastCursor = cursor
        lastSource = source
        lastIfNoneMatch = ifNoneMatch
        if let err = nextError { throw err }
        if nextNotModified {
            return InboxResponse(page: nil, etag: nextEtag, notModified: true)
        }
        let page = InboxPage(
            total: nextItems.count,
            items: nextItems,
            nextCursor: nextHasMore ? "next" : nil
        )
        return InboxResponse(page: page, etag: nextEtag, notModified: false)
    }

    public func markRead(id: String, read: Bool) async throws {
        markReadCalls.append((id: id, read: read))
        if let err = nextMarkReadError {
            // Clear so a follow-up call can succeed if the test stages it.
            nextMarkReadError = nil
            throw err
        }
    }
}
