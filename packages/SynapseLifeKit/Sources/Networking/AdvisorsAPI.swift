import Foundation
import Models

/// Transport for the AI Advisors surface. Two endpoints:
///   - `GET /api/ai-advisors` returns the persona list (already test-covered
///     by `AdvisorsRepositoryTests` against `URLProtocolStub`).
///   - `POST /api/ai-advisors/[id]/chat` returns an SSE stream of the shape
///     `data: {"text":"…"}\n\n` and a final `data: {"done":true,"threadId":"…"}\n\n`.
///
/// `streamChat` returns an `AsyncThrowingStream<String, Error>` of decoded
/// token deltas — view models append to the in-flight assistant message and
/// the stream terminates naturally when the server sends `done`. Cancel by
/// cancelling the consuming Task.
public protocol AdvisorsAPI: Sendable {
    func list() async throws -> [Advisor]
    func streamChat(
        advisorId: String,
        userMessage: String,
        threadId: String?
    ) -> AsyncThrowingStream<ChatDelta, Error>
}

/// One streamed event from the chat endpoint. `text` carries a token chunk;
/// `done` carries the persisted thread id; `error` carries a string the
/// server emitted before terminating the stream.
public enum ChatDelta: Sendable, Equatable {
    case text(String)
    case done(threadId: String?)
    case error(String)
}

/// Live `/api/ai-advisors` implementation. The streaming path bypasses the
/// typed `APIClient.send()` because SSE needs raw byte access; non-stream
/// reads still go through the actor for retry + auth.
public struct LiveAdvisorsAPI: AdvisorsAPI {
    private let client: APIClient
    private let baseURL: URL
    private let session: URLSession

    public init(client: APIClient) {
        self.client = client
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
    }

    public func list() async throws -> [Advisor] {
        let endpoint = Endpoint<AdvisorsResponse>(
            method: .get,
            path: "api/ai-advisors"
        )
        let envelope = try await client.send(endpoint)
        return envelope.advisors
    }

    public func streamChat(
        advisorId: String,
        userMessage: String,
        threadId: String?
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        let url = baseURL.appendingPathComponent("api/ai-advisors/\(advisorId)/chat")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    var body: [String: Any] = ["message": userMessage]
                    if let threadId { body["threadId"] = threadId }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.transport
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw APIError.server(status: http.statusCode)
                    }
                    // Drain bytes manually so SSE blocks split on `\n\n`
                    // regardless of whether the transport flushes per
                    // line. URLSession.bytes.lines splits on a single LF
                    // which we'd then need to re-coalesce; reading raw
                    // bytes lets us emit deltas as soon as a complete
                    // event boundary arrives.
                    var pending: [UInt8] = []
                    for try await byte in bytes {
                        if Task.isCancelled {
                            continuation.finish(throwing: APIError.cancelled)
                            return
                        }
                        pending.append(byte)
                        if let yielded = Self.drainCompleteBlocks(&pending) {
                            for delta in yielded {
                                continuation.yield(delta)
                                if case .done = delta {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    // Stream ended without a `\n\n` terminator on the
                    // tail block; parse whatever we have left.
                    if !pending.isEmpty,
                       let trailing = String(bytes: pending, encoding: .utf8),
                       let delta = SSEParser.parseDataBlock(trailing) {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: APIError.cancelled)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish(throwing: APIError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Walk `pending` looking for the SSE event terminator `\n\n`. Each
    /// time one is found, parse the block and return the resulting delta,
    /// trimming the consumed bytes off the front of `pending`. Returns an
    /// array of zero or more parsed deltas. Mutates the buffer in place.
    static func drainCompleteBlocks(_ pending: inout [UInt8]) -> [ChatDelta]? {
        var out: [ChatDelta] = []
        while true {
            guard let boundary = Self.indexOfDoubleNewline(in: pending) else {
                break
            }
            let blockBytes = Array(pending[..<boundary])
            // Remove the consumed block plus the `\n\n` terminator.
            pending.removeFirst(boundary + 2)
            if let block = String(bytes: blockBytes, encoding: .utf8),
               let delta = SSEParser.parseDataBlock(block) {
                out.append(delta)
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Find the first `\n\n` (or `\r\n\r\n`) sequence in `bytes`. The
    /// returned index points at the **first** byte of the terminator, not
    /// past it.
    static func indexOfDoubleNewline(in bytes: [UInt8]) -> Int? {
        let lf: UInt8 = 0x0A
        let cr: UInt8 = 0x0D
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == lf, bytes[i + 1] == lf {
                return i
            }
            if i < bytes.count - 3,
               bytes[i] == cr, bytes[i + 1] == lf,
               bytes[i + 2] == cr, bytes[i + 3] == lf {
                return i
            }
            i += 1
        }
        return nil
    }
}

/// Pure SSE block parser. One block looks like:
/// ```
/// data: {"text":"hello"}
/// ```
/// trailing newlines are already stripped by the line iterator. Each
/// `data:` line carries one JSON object — `{ text }`, `{ done, threadId }`,
/// or `{ error }`.
enum SSEParser {
    static func parseDataBlock(_ block: String) -> ChatDelta? {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // The block may contain multiple `data:` lines; the SSE spec says
        // concatenate with `\n`. Practically, our server emits one per
        // block, but we honor the spec.
        let dataLines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> Substring? in
                if line.hasPrefix("data:") {
                    return line.dropFirst("data:".count)
                }
                return nil
            }
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let text = json["text"] as? String {
            return .text(text)
        }
        if let done = json["done"] as? Bool, done {
            let threadId = json["threadId"] as? String
            return .done(threadId: threadId)
        }
        if let err = json["error"] as? String {
            return .error(err)
        }
        return nil
    }
}

// MARK: - Mock

/// Test double. `setListResponse` controls the persona list; `setStream`
/// queues a sequence of `ChatDelta`s that `streamChat` replays in order.
/// Use `setStreamError` to surface a transport failure.
public actor MockAdvisorsAPI: AdvisorsAPI {
    private var listResponse: [Advisor] = []
    private var listError: Error?
    private var queuedDeltas: [ChatDelta] = []
    private var deltaError: Error?
    /// Optional per-delta delay so cancellation tests can interrupt
    /// mid-stream deterministically.
    private var deltaDelay: Duration = .zero
    public private(set) var listCallCount: Int = 0
    public private(set) var streamCallCount: Int = 0
    public private(set) var lastStreamAdvisorId: String?
    public private(set) var lastStreamMessage: String?
    public private(set) var lastStreamThreadId: String?

    public init() {}

    public func setListResponse(_ advisors: [Advisor]) {
        self.listResponse = advisors
        self.listError = nil
    }

    public func setListError(_ error: Error) {
        self.listError = error
    }

    public func setStream(_ deltas: [ChatDelta], perDeltaDelay: Duration = .zero) {
        self.queuedDeltas = deltas
        self.deltaError = nil
        self.deltaDelay = perDeltaDelay
    }

    public func setStreamError(_ error: Error) {
        self.deltaError = error
    }

    public func list() async throws -> [Advisor] {
        listCallCount += 1
        if let err = listError { throw err }
        return listResponse
    }

    public nonisolated func streamChat(
        advisorId: String,
        userMessage: String,
        threadId: String?
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                await self.recordStreamCall(
                    advisorId: advisorId,
                    message: userMessage,
                    threadId: threadId
                )
                if let err = await self.deltaError {
                    continuation.finish(throwing: err)
                    return
                }
                let snapshot = await self.queuedDeltas
                let delay = await self.deltaDelay
                for delta in snapshot {
                    if Task.isCancelled {
                        continuation.finish(throwing: APIError.cancelled)
                        return
                    }
                    if delay > .zero {
                        do {
                            try await Task.sleep(for: delay)
                        } catch {
                            continuation.finish(throwing: APIError.cancelled)
                            return
                        }
                    }
                    continuation.yield(delta)
                    if case .done = delta {
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func recordStreamCall(advisorId: String, message: String, threadId: String?) {
        streamCallCount += 1
        lastStreamAdvisorId = advisorId
        lastStreamMessage = message
        lastStreamThreadId = threadId
    }
}
