import Foundation
import Models

/// Holds the latest `ApprovalsBundle` and the last-seen ETag. Concurrency-safe
/// by virtue of being an actor; views read snapshots via the `@MainActor`
/// view model. Mirrors the M2 `SpotlightRepository` shape.
public actor ApprovalsRepository {
    private let api: ApprovalsAPI
    public private(set) var bundle: ApprovalsBundle = ApprovalsBundle(approvals: [], receipts: [])
    private var etag: String?

    public init(api: ApprovalsAPI) {
        self.api = api
    }

    /// Re-fetch the bundle. A 304 leaves the cache untouched but records the
    /// (possibly refreshed) ETag.
    public func refresh() async throws {
        let response = try await api.list(ifNoneMatch: etag)
        if response.notModified {
            if let newETag = response.etag { etag = newETag }
            return
        }
        if let bundle = response.bundle {
            self.bundle = bundle
        }
        if let newETag = response.etag { etag = newETag }
    }

    /// Read-only snapshot of the current bundle (for sync access between
    /// refreshes).
    public func snapshot() -> ApprovalsBundle { bundle }
}
