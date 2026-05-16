import Foundation
import Models
import Networking

/// Concurrency-safe cache for the People list. Mirrors the
/// [[ApprovalsRepository]] / [[SpotlightRepository]] shape: actor, ETag-aware,
/// 304 leaves the cache intact.
public actor PeopleRepository {
    private let api: PeopleAPI
    public private(set) var people: [Person] = []
    private var etag: String?

    public init(api: PeopleAPI) {
        self.api = api
    }

    public func refresh() async throws {
        let response = try await api.list(ifNoneMatch: etag)
        if response.notModified {
            if let newETag = response.etag { etag = newETag }
            return
        }
        if let people = response.people {
            self.people = people
        }
        if let newETag = response.etag { etag = newETag }
    }

    public func snapshot() -> [Person] { people }

    public func dossier(for identity: String) async throws -> PersonDossier {
        try await api.dossier(for: identity)
    }
}
