import Foundation
import Models
import Networking

/// Server scope filter. The Synapse v2 server today returns the full event
/// list; this enum is forward-compatible with the planned scope param.
public enum SpotlightScope: String, Sendable, CaseIterable, Equatable {
    case picks
    case detections
    case all
}

public protocol SpotlightAPI: Sendable {
    func list(
        scope: SpotlightScope?,
        cursor: String?,
        ifNoneMatch: String?
    ) async throws -> SpotlightResponse
}

/// Wraps the decoded page with the transport-level ETag and 304 signal so
/// the repository can decide whether to overwrite its cache.
public struct SpotlightResponse: Sendable, Equatable {
    public let page: SpotlightPage?
    public let etag: String?
    public let notModified: Bool

    public init(page: SpotlightPage?, etag: String?, notModified: Bool) {
        self.page = page
        self.etag = etag
        self.notModified = notModified
    }
}

/// Live implementation composing `Endpoint`s against `/api/spotlight`.
/// The 304 path requires reading the raw HTTP status and headers, so this
/// path drops down to URLSession directly — `APIClient`'s typed send() treats
/// 304 as a non-2xx server error.
public struct LiveSpotlightAPI: SpotlightAPI {
    private let client: APIClient
    private let baseURL: URL
    private let session: URLSession

    public init(client: APIClient) {
        self.client = client
        // Tease the URL + session out of the client for the raw-response
        // path. Cheap because APIClient was built with them.
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
    }

    public func list(
        scope: SpotlightScope?,
        cursor: String?,
        ifNoneMatch: String?
    ) async throws -> SpotlightResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/spotlight"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = []
        if let scope { queryItems.append(URLQueryItem(name: "scope", value: scope.rawValue)) }
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if !queryItems.isEmpty { components?.queryItems = queryItems }
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
            return SpotlightResponse(page: nil, etag: etag, notModified: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let page = try JSONDecoder.synnapseSpotlight.decode(SpotlightPage.self, from: data)
            return SpotlightResponse(page: page, etag: etag, notModified: false)
        } catch {
            throw APIError.decoding
        }
    }
}

/// Mock for unit tests and SwiftUI previews. Fully concurrency-safe.
public actor MockSpotlightAPI: SpotlightAPI {
    private var nextPage: SpotlightPage = SpotlightPage(events: [], nextCursor: nil)
    private var nextError: Error?
    private var delay: Duration = .zero
    public private(set) var callCount: Int = 0
    public private(set) var lastScope: SpotlightScope?
    public private(set) var lastCursor: String?

    public init() {}

    public func setNextPage(_ page: SpotlightPage) {
        nextPage = page
        nextError = nil
    }

    public func setNextError(_ error: Error) {
        nextError = error
    }

    public func setDelay(_ d: Duration) {
        delay = d
    }

    public func list(
        scope: SpotlightScope?,
        cursor: String?,
        ifNoneMatch: String?
    ) async throws -> SpotlightResponse {
        callCount += 1
        lastScope = scope
        lastCursor = cursor
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let err = nextError { throw err }
        return SpotlightResponse(page: nextPage, etag: nil, notModified: false)
    }
}
