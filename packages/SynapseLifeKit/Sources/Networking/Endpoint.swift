import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Typed endpoint. `Response` is the decoded payload the caller expects.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public let method: HTTPMethod
    public let path: String
    public let query: [URLQueryItem]
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: HTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

extension Endpoint {
    /// Compose a final request URL against a base URL. Throws if the result
    /// cannot be expressed as a valid `URL` (path or query corrupt).
    public func url(relativeTo base: URL) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let baseWithSlash = URL(string: base.absoluteString.hasSuffix("/")
            ? base.absoluteString
            : base.absoluteString + "/") else {
            throw URLError(.badURL)
        }
        guard let joined = URL(string: trimmed, relativeTo: baseWithSlash)?.absoluteURL else {
            throw URLError(.badURL)
        }
        guard var components = URLComponents(url: joined, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let final = components.url else { throw URLError(.badURL) }
        return final
    }

    /// Merge default headers with endpoint headers. Endpoint headers win on key
    /// collision so callers can override per-request.
    public func merged(defaults: [String: String]) -> [String: String] {
        var out = defaults
        for (k, v) in headers { out[k] = v }
        return out
    }
}
