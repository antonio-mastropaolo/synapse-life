import Foundation
import Models
import Networking

/// Test + preview double for the People surface. Lives in `Features` (not
/// `Networking`) so the SnapshotTests target — which only depends on
/// Features / Models / DesignSystem — can construct view models for
/// deterministic snapshot rendering.
public actor MockPeopleAPI: PeopleAPI {
    public private(set) var callCount: Int = 0
    public private(set) var lastIfNoneMatch: String?
    private var nextPeople: [Person] = []
    private var nextDossier: PersonDossier?
    private var nextEtag: String?
    private var nextNotModified: Bool = false
    private var nextError: Error?

    public init() {}

    public func setNextPeople(_ people: [Person], etag: String? = nil) {
        nextPeople = people
        nextEtag = etag
        nextError = nil
        nextNotModified = false
    }

    public func setNotModified(etag: String?) {
        nextNotModified = true
        nextEtag = etag
        nextError = nil
    }

    public func setNextDossier(_ dossier: PersonDossier) {
        nextDossier = dossier
    }

    public func setNextError(_ error: Error) {
        nextError = error
    }

    public func list(ifNoneMatch: String?) async throws -> PeopleResponse {
        callCount += 1
        lastIfNoneMatch = ifNoneMatch
        if let err = nextError { throw err }
        if nextNotModified {
            return PeopleResponse(people: nil, etag: nextEtag, notModified: true)
        }
        return PeopleResponse(people: nextPeople, etag: nextEtag, notModified: false)
    }

    public func dossier(for identity: String) async throws -> PersonDossier {
        if let err = nextError { throw err }
        if let d = nextDossier { return d }
        if let person = nextPeople.first(where: { $0.identity == identity }) {
            return PersonDossier(person: person, recentMessages: [], openActionItems: [])
        }
        throw APIError.server(status: 404)
    }
}
