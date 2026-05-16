import Foundation
import Models

/// Transport for the Octagon side of the app. Two endpoints:
///
///   - `GET /api/finance/octagon/[vendor]` — company brief for one vendor.
///     The synapse-v2 server caches 24h in sqlite; first call ~10–30s,
///     subsequent calls <50ms.
///   - `GET /api/finance/memberships` — recurring subscription cards. Not
///     yet exposed by synapse-v2 as of M8 (the web app derives them client
///     side from transactions); the native client treats the endpoint as
///     **forward-compat** and tolerates a 404 by returning an empty list,
///     mirroring `LiveLifeAPI`'s contract gate.
public protocol OctagonAPI: Sendable {
    func brief(vendor: String) async throws -> OctagonVendor
    func memberships(cursor: String?) async throws -> MembershipsResponse
}

public struct LiveOctagonAPI: OctagonAPI {
    private let baseURL: URL
    private let session: URLSession
    /// Toggle for the memberships endpoint. Defaults to `false` while the
    /// server route is in flight; flip to `true` once it lands.
    public let membershipsContractLive: Bool

    public init(client: APIClient, membershipsContractLive: Bool = false) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
        self.membershipsContractLive = membershipsContractLive
    }

    public func brief(vendor: String) async throws -> OctagonVendor {
        let encoded = vendor.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? vendor
        let url = baseURL.appendingPathComponent("api/finance/octagon/\(encoded)")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(OctagonBriefEnvelope.self, from: data)
            guard envelope.ok else {
                // Server flipped `ok: false`. Surface as a server error
                // so the repository can paint the inspector's failure card.
                throw APIError.server(status: 500)
            }
            return envelope.brief
        } catch is DecodingError {
            throw APIError.decoding
        }
    }

    public func memberships(cursor: String?) async throws -> MembershipsResponse {
        guard membershipsContractLive else {
            return MembershipsResponse(memberships: [], nextCursor: nil)
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/finance/memberships"),
            resolvingAgainstBaseURL: false
        )
        if let cursor {
            components?.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        guard let url = components?.url else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        if http.statusCode == 404 {
            return MembershipsResponse(memberships: [], nextCursor: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(MembershipsResponse.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

public actor MockOctagonAPI: OctagonAPI {
    private var nextBrief: OctagonVendor?
    private var briefError: Error?
    private var nextMemberships: [MembershipCard] = []
    private var nextCursor: String?
    private var membershipsError: Error?
    public private(set) var briefCallCount: Int = 0
    public private(set) var lastBriefVendor: String?
    public private(set) var membershipsCallCount: Int = 0
    public private(set) var lastMembershipsCursor: String?

    public init() {}

    public func setBrief(_ brief: OctagonVendor) {
        self.nextBrief = brief
        self.briefError = nil
    }

    public func setBriefError(_ error: Error) {
        self.briefError = error
    }

    public func setMemberships(_ cards: [MembershipCard], nextCursor: String? = nil) {
        self.nextMemberships = cards
        self.nextCursor = nextCursor
        self.membershipsError = nil
    }

    public func setMembershipsError(_ error: Error) {
        self.membershipsError = error
    }

    public func brief(vendor: String) async throws -> OctagonVendor {
        briefCallCount += 1
        lastBriefVendor = vendor
        if let err = briefError { throw err }
        guard let brief = nextBrief else { throw APIError.server(status: 404) }
        return brief
    }

    public func memberships(cursor: String?) async throws -> MembershipsResponse {
        membershipsCallCount += 1
        lastMembershipsCursor = cursor
        if let err = membershipsError { throw err }
        return MembershipsResponse(memberships: nextMemberships, nextCursor: nextCursor)
    }
}
