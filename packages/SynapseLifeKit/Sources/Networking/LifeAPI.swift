import Foundation
import Models

/// LIFE feed transport. Synapse v2 does not yet expose a uniform
/// `/api/life/entries` route; the closest thing on the server is the
/// `/api/life/overview` aggregator plus `/api/life/outstanding`. The
/// native client treats those as forward-compat — we issue an HTTP GET to
/// `/api/life/entries`, decode `{ entries: [...] }` if present, and
/// otherwise fall back to a deterministic "boot" line so the terminal
/// has something to render. Once the server lands the real route this
/// path becomes live without any client changes.
public struct LifeEntriesAPIResponse: Sendable, Equatable {
    public let entries: [LifeEntry]
    public let nextCursor: String?

    public init(entries: [LifeEntry], nextCursor: String? = nil) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

public protocol LifeAPI: Sendable {
    func entries(cursor: String?) async throws -> LifeEntriesAPIResponse
}

private struct LifeEntriesEnvelope: Decodable {
    let entries: [LifeEntry]?
    let nextCursor: String?
}

public struct LiveLifeAPI: LifeAPI {
    private let baseURL: URL
    private let session: URLSession
    public let serverContractLive: Bool

    /// `serverContractLive` defaults to `false` because the synapse-v2
    /// server has not implemented `/api/life/entries` yet. The view model
    /// reads this flag and uses the deterministic boot stream when false,
    /// so we don't issue a 404-shaped GET on every refresh.
    public init(client: APIClient, serverContractLive: Bool = false) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
        self.serverContractLive = serverContractLive
    }

    public func entries(cursor: String?) async throws -> LifeEntriesAPIResponse {
        guard serverContractLive else {
            return LifeEntriesAPIResponse(entries: [], nextCursor: nil)
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/life/entries"),
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
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(LifeEntriesEnvelope.self, from: data)
            return LifeEntriesAPIResponse(
                entries: envelope.entries ?? [],
                nextCursor: envelope.nextCursor
            )
        } catch {
            throw APIError.decoding
        }
    }
}

public actor MockLifeAPI: LifeAPI {
    private var nextEntries: [LifeEntry] = []
    private var nextCursor: String?
    private var nextError: Error?
    public private(set) var callCount: Int = 0

    public init() {}

    public func setEntries(_ entries: [LifeEntry], cursor: String? = nil) {
        self.nextEntries = entries
        self.nextCursor = cursor
        self.nextError = nil
    }

    public func setNextError(_ error: Error) {
        self.nextError = error
    }

    public func entries(cursor: String?) async throws -> LifeEntriesAPIResponse {
        callCount += 1
        if let err = nextError { throw err }
        return LifeEntriesAPIResponse(entries: nextEntries, nextCursor: nextCursor)
    }
}
