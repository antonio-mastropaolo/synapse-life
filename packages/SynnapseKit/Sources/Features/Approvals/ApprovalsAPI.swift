import Foundation
import Models
import Networking

/// Result of an approvals fetch — carries ETag + 304 signal so the
/// repository can keep its cache when the server confirms nothing changed.
public struct ApprovalsResponse: Sendable, Equatable {
    public let bundle: ApprovalsBundle?
    public let etag: String?
    public let notModified: Bool

    public init(bundle: ApprovalsBundle?, etag: String?, notModified: Bool) {
        self.bundle = bundle
        self.etag = etag
        self.notModified = notModified
    }
}

public protocol ApprovalsAPI: Sendable {
    func list(ifNoneMatch: String?) async throws -> ApprovalsResponse
}

/// Decoded directly from a hypothetical bundled endpoint at
/// `/api/approvals/bundle` (server contract not yet live). The wire shape is
/// intentionally permissive — both `approvals` and `receipts` may be omitted.
private struct BundleEnvelope: Decodable {
    let approvals: [ServerApprovalRow]?
    let receipts: [ServerReceiptRow]?
}

/// Live implementation. Tolerates two server shapes:
///   1. Bundled: `GET /api/approvals/bundle` returns `{ approvals, receipts }`.
///      Synapse v2 does NOT yet expose this; when it lands, the client picks
///      it up for free.
///   2. Split: `GET /api/approvals` + `GET /api/receipts`. Today's reality.
///
/// The split path issues both requests in parallel via `async let` and stitches
/// the bundle. ETag is taken from the approvals endpoint only — receipts has
/// no stable ETag today.
public struct LiveApprovalsAPI: ApprovalsAPI {
    private let baseURL: URL
    private let session: URLSession
    private let preferBundled: Bool

    public init(client: APIClient, preferBundled: Bool = false) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
        self.preferBundled = preferBundled
    }

    public func list(ifNoneMatch: String?) async throws -> ApprovalsResponse {
        if preferBundled {
            return try await fetchBundled(ifNoneMatch: ifNoneMatch)
        }
        return try await fetchSplit(ifNoneMatch: ifNoneMatch)
    }

    // MARK: - Bundled path (forward-compat)

    private func fetchBundled(ifNoneMatch: String?) async throws -> ApprovalsResponse {
        let url = baseURL.appendingPathComponent("api/approvals/bundle")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag")
        if http.statusCode == 304 {
            return ApprovalsResponse(bundle: nil, etag: etag, notModified: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(BundleEnvelope.self, from: data)
            let approvals = (envelope.approvals ?? []).map(Approval.fromServerRow)
            let receipts = (envelope.receipts ?? []).map(Receipt.fromServerRow)
            return ApprovalsResponse(
                bundle: ApprovalsBundle(approvals: approvals, receipts: receipts),
                etag: etag,
                notModified: false
            )
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: - Split path (today's server)

    private func fetchSplit(ifNoneMatch: String?) async throws -> ApprovalsResponse {
        async let approvalsResult = fetchApprovals(ifNoneMatch: ifNoneMatch)
        async let receiptsResult = fetchReceipts()
        let (approvalsTuple, receipts) = try await (approvalsResult, receiptsResult)
        let (approvals, etag, notModified) = approvalsTuple
        if notModified {
            return ApprovalsResponse(bundle: nil, etag: etag, notModified: true)
        }
        return ApprovalsResponse(
            bundle: ApprovalsBundle(approvals: approvals, receipts: receipts),
            etag: etag,
            notModified: false
        )
    }

    private func fetchApprovals(
        ifNoneMatch: String?
    ) async throws -> ([Approval], String?, Bool) {
        let url = baseURL.appendingPathComponent("api/approvals")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag")
        if http.statusCode == 304 {
            return ([], etag, true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(ServerApprovalsListResponse.self, from: data)
            return (envelope.approvals.map(Approval.fromServerRow), etag, false)
        } catch {
            throw APIError.decoding
        }
    }

    private func fetchReceipts() async throws -> [Receipt] {
        let url = baseURL.appendingPathComponent("api/receipts")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(ServerReceiptsListResponse.self, from: data)
            return envelope.receipts.map(Receipt.fromServerRow)
        } catch {
            throw APIError.decoding
        }
    }
}

/// Test + preview double. Hands back whatever the caller stages.
public actor MockApprovalsAPI: ApprovalsAPI {
    public private(set) var callCount: Int = 0
    public private(set) var lastIfNoneMatch: String?
    private var nextBundle: ApprovalsBundle = ApprovalsBundle(approvals: [], receipts: [])
    private var nextEtag: String?
    private var nextNotModified: Bool = false
    private var nextError: Error?

    public init() {}

    public func setNextBundle(_ bundle: ApprovalsBundle, etag: String? = nil) {
        nextBundle = bundle
        nextEtag = etag
        nextError = nil
        nextNotModified = false
    }

    public func setNotModified(etag: String?) {
        nextNotModified = true
        nextEtag = etag
        nextError = nil
    }

    public func setNextError(_ error: Error) {
        nextError = error
    }

    public func list(ifNoneMatch: String?) async throws -> ApprovalsResponse {
        callCount += 1
        lastIfNoneMatch = ifNoneMatch
        if let err = nextError { throw err }
        if nextNotModified {
            return ApprovalsResponse(bundle: nil, etag: nextEtag, notModified: true)
        }
        return ApprovalsResponse(bundle: nextBundle, etag: nextEtag, notModified: false)
    }
}
