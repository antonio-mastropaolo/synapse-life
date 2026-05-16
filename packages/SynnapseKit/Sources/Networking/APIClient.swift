import Foundation

public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case server(status: Int)
    case transport
    case decoding
    case cancelled
    case badURL
}

/// Provides bearer tokens and a one-shot refresh hook. The client calls
/// `refresh()` at most once per request lifetime when it sees a 401.
public protocol AuthInterceptor: Sendable {
    func currentAccessToken() async -> String?
    func refresh() async throws -> String
}

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(50)) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero)
}

public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let defaultHeaders: [String: String]
    private let auth: AuthInterceptor?
    private let retry: RetryPolicy
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        defaultHeaders: [String: String] = ["Accept": "application/json"],
        auth: AuthInterceptor? = nil,
        retry: RetryPolicy = RetryPolicy(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.defaultHeaders = defaultHeaders
        self.auth = auth
        self.retry = retry
        self.decoder = decoder
    }

    public func send<R>(_ endpoint: Endpoint<R>) async throws -> R {
        let request = try await makeRequest(endpoint)
        let (data, response) = try await execute(
            request,
            originalEndpoint: endpoint,
            didRefresh: false,
            attempt: 1
        )
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func makeRequest<R>(_ endpoint: Endpoint<R>) async throws -> URLRequest {
        let url: URL
        do {
            url = try endpoint.url(relativeTo: baseURL)
        } catch {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        var headers = endpoint.merged(defaults: defaultHeaders)
        if let token = await auth?.currentAccessToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return request
    }

    private func execute<R>(
        _ request: URLRequest,
        originalEndpoint: Endpoint<R>,
        didRefresh: Bool,
        attempt: Int
    ) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.transport }

            if http.statusCode == 401 {
                guard !didRefresh, let auth else { throw APIError.unauthorized }
                _ = try await auth.refresh()
                let refreshed = try await makeRequest(originalEndpoint)
                return try await execute(
                    refreshed,
                    originalEndpoint: originalEndpoint,
                    didRefresh: true,
                    attempt: attempt
                )
            }

            if (500..<600).contains(http.statusCode), attempt < retry.maxAttempts {
                try await backoff(attempt: attempt)
                return try await execute(
                    request,
                    originalEndpoint: originalEndpoint,
                    didRefresh: didRefresh,
                    attempt: attempt + 1
                )
            }
            return (data, response)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw APIError.cancelled
        }
    }

    private func backoff(attempt: Int) async throws {
        // Exponential: base * 2^(attempt-1). Cancellation-aware.
        let multiplier = 1 << (attempt - 1)
        let delay = retry.baseDelay * multiplier
        try await Task.sleep(for: delay)
    }
}
