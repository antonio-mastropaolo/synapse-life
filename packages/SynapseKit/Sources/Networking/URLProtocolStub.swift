import Foundation

/// Test-only URLProtocol that returns canned responses and records every
/// request it saw. Handlers are scoped per-session via a session token carried
/// in `URLSessionConfiguration.httpAdditionalHeaders`, so tests running in
/// parallel do not stomp on each other.
public final class URLProtocolStub: URLProtocol, @unchecked Sendable {

    public struct Response: Sendable {
        public let statusCode: Int
        public let headers: [String: String]
        public let body: Data

        public init(statusCode: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    public typealias Handler = @Sendable (URLRequest) -> Result<Response, Error>

    public static let tokenHeader = "X-Synapse-Stub-Token"

    private struct Box {
        var handler: Handler
        var recorded: [URLRequest] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var boxes: [String: Box] = [:]

    public static func makeSession(_ handler: @escaping Handler) -> URLSession {
        let token = UUID().uuidString
        lock.lock()
        boxes[token] = Box(handler: handler)
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        config.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: config)
    }

    /// Drains and returns the requests recorded for a session. Pass the
    /// session you got from `makeSession(_:)`.
    public static func requests(for session: URLSession) -> [URLRequest] {
        guard let token = session.configuration.httpAdditionalHeaders?[tokenHeader] as? String else {
            return []
        }
        lock.lock(); defer { lock.unlock() }
        return boxes[token]?.recorded ?? []
    }

    public static func releaseSession(_ session: URLSession) {
        guard let token = session.configuration.httpAdditionalHeaders?[tokenHeader] as? String else {
            return
        }
        lock.lock(); defer { lock.unlock() }
        boxes.removeValue(forKey: token)
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let token = request.value(forHTTPHeaderField: Self.tokenHeader)
            ?? (URLSession.shared.configuration.httpAdditionalHeaders?[Self.tokenHeader] as? String)

        Self.lock.lock()
        let handler: Handler? = token.flatMap { Self.boxes[$0]?.handler }
        if let token, var box = Self.boxes[token] {
            box.recorded.append(request)
            Self.boxes[token] = box
        }
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch handler(request) {
        case .success(let stub):
            let resolved: URL = request.url ?? URL(fileURLWithPath: "/")
            guard let response = HTTPURLResponse(
                url: resolved,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}
}
