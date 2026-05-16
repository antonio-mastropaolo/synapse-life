import Foundation
import Models

/// Response from the sequences list endpoint, carrying the typed page + the
/// transport-level ETag so the repository can keep its cache when the server
/// emits 304.
public struct SequencesListResponse: Sendable, Equatable {
    public let total: Int
    public let sequences: [Sequence]
    public let etag: String?
    public let notModified: Bool

    public init(total: Int, sequences: [Sequence], etag: String?, notModified: Bool) {
        self.total = total
        self.sequences = sequences
        self.etag = etag
        self.notModified = notModified
    }
}

/// Status filter accepted by `GET /api/sequences?status=`. Mirrors the
/// server-side STATUSES set.
public enum SequencesStatusFilter: String, Sendable, CaseIterable, Equatable {
    case active
    case paused
    case replied
    case completed
    case all
}

/// Stage-draft upsert payload. The server contract for this PATCH is NOT
/// yet live — see manifest. The native client posts a typed body so the
/// payload is in lockstep with what the server will accept; until then,
/// `LiveSequencesAPI.upsertDraft(...)` returns the input echoed back so
/// the editor can demonstrate save-feedback without a real round trip.
public struct StageDraftDelta: Codable, Sendable, Hashable {
    public let sequenceId: String
    public let stageId: String
    public let subject: String
    public let body: String

    public init(sequenceId: String, stageId: String, subject: String, body: String) {
        self.sequenceId = sequenceId
        self.stageId = stageId
        self.subject = subject
        self.body = body
    }
}

public protocol SequencesAPI: Sendable {
    func list(
        status: SequencesStatusFilter,
        ifNoneMatch: String?
    ) async throws -> SequencesListResponse

    /// Read a single sequence by id. The server does not currently expose
    /// `GET /api/sequences/<id>` — for now this is implemented client-side
    /// by filtering the list. The contract is here so callers can target it
    /// when the server lands a dedicated endpoint.
    func get(id: String) async throws -> Sequence?

    /// DRAFT-ONLY upsert. There is NO send-from-client path. The actual
    /// outbound queue runs on the server (`POST /api/sequences/tick`). This
    /// method only persists the operator's edits to a stage's subject/body.
    func upsertDraft(_ delta: StageDraftDelta) async throws -> StageDraftDelta
}

/// Live wire implementation. Drops down to raw URLSession for the GET path
/// because the 304 short-circuit can't be expressed through APIClient's
/// typed `send()`. Mirrors the shape of `LiveSpotlightAPI`.
public struct LiveSequencesAPI: SequencesAPI {
    private let baseURL: URL
    private let session: URLSession
    private let serverDraftContractLive: Bool

    /// `serverDraftContractLive` defaults to `false` — Synapse v2 has no
    /// PATCH endpoint for stage drafts yet. When the route lands, flip this
    /// at the call site and the native client starts persisting against the
    /// real backend.
    public init(client: APIClient, serverDraftContractLive: Bool = false) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
        self.serverDraftContractLive = serverDraftContractLive
    }

    public func list(
        status: SequencesStatusFilter,
        ifNoneMatch: String?
    ) async throws -> SequencesListResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/sequences"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "status", value: status.rawValue),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components?.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        let etag = http.value(forHTTPHeaderField: "ETag")
            ?? http.value(forHTTPHeaderField: "Etag")

        if http.statusCode == 304 {
            return SequencesListResponse(total: 0, sequences: [], etag: etag, notModified: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(ServerSequencesListResponse.self, from: data)
            let projected = envelope.sequences.map(Sequence.fromServerRow)
            return SequencesListResponse(
                total: envelope.total,
                sequences: projected,
                etag: etag,
                notModified: false
            )
        } catch {
            throw APIError.decoding
        }
    }

    public func get(id: String) async throws -> Sequence? {
        let response = try await list(status: .all, ifNoneMatch: nil)
        return response.sequences.first { $0.id == id }
    }

    public func upsertDraft(_ delta: StageDraftDelta) async throws -> StageDraftDelta {
        guard serverDraftContractLive else {
            // The server has no PATCH route today. Echo the delta back so
            // the view model can flip its dirty/clean indicator on a
            // round-trip basis without depending on a non-existent endpoint.
            // This is documented in the manifest as the "server contract
            // pending" path.
            return delta
        }

        let url = baseURL.appendingPathComponent("api/sequences/\(delta.sequenceId)/stages/\(delta.stageId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = try JSONEncoder().encode(delta)
        request.httpBody = payload

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(StageDraftDelta.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

/// Test + preview double. Concurrency-safe.
public actor MockSequencesAPI: SequencesAPI {
    public private(set) var listCallCount: Int = 0
    public private(set) var lastIfNoneMatch: String?
    public private(set) var upsertCallCount: Int = 0
    public private(set) var lastUpsertDelta: StageDraftDelta?

    private var nextSequences: [Sequence] = []
    private var nextEtag: String?
    private var nextNotModified: Bool = false
    private var nextError: Error?
    private var upsertError: Error?

    public init() {}

    public func setNextList(_ sequences: [Sequence], etag: String? = nil) {
        nextSequences = sequences
        nextEtag = etag
        nextNotModified = false
        nextError = nil
    }

    public func setNotModified(etag: String?) {
        nextNotModified = true
        nextEtag = etag
        nextError = nil
    }

    public func setNextError(_ error: Error) {
        nextError = error
    }

    public func setUpsertError(_ error: Error) {
        upsertError = error
    }

    public func list(
        status: SequencesStatusFilter,
        ifNoneMatch: String?
    ) async throws -> SequencesListResponse {
        listCallCount += 1
        lastIfNoneMatch = ifNoneMatch
        if let err = nextError { throw err }
        if nextNotModified {
            return SequencesListResponse(
                total: 0,
                sequences: [],
                etag: nextEtag,
                notModified: true
            )
        }
        return SequencesListResponse(
            total: nextSequences.count,
            sequences: nextSequences,
            etag: nextEtag,
            notModified: false
        )
    }

    public func get(id: String) async throws -> Sequence? {
        if let err = nextError { throw err }
        return nextSequences.first { $0.id == id }
    }

    public func upsertDraft(_ delta: StageDraftDelta) async throws -> StageDraftDelta {
        upsertCallCount += 1
        lastUpsertDelta = delta
        if let err = upsertError { throw err }
        return delta
    }
}
