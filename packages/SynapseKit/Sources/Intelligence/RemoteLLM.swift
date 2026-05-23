import Foundation
import Networking

/// Remote LLM client. Talks to our own `POST /api/llm/proxy` endpoint;
/// the proxy forwards to Claude or GPT depending on a header the client
/// sets. The wire shape (SSE) matches what `AdvisorsAPI` already speaks,
/// so we'll reuse the same parser when Phase 3 wires up the real call.
///
/// ## SSE frame shape
///
/// One streaming response is a sequence of `data:` blocks separated by
/// `\n\n`. Each block carries one JSON object:
///
/// ```
/// data: {"text":"partial"}\n\n
/// data: {"tool":{"id":"…","name":"…","arguments":"{…}"}}\n\n
/// data: {"done":true,"usage":{"prompt":42,"completion":17}}\n\n
/// ```
///
/// Errors terminate the stream with `data: {"error":"…"}\n\n` followed
/// by a normal SSE close. The parsing logic in `AdvisorsAPI`'s
/// `SSEParser.parseDataBlock(...)` is the reference shape; Phase 3 will
/// lift it into a shared module or duplicate it here on purpose.
public actor RemoteLLM: LLMClient {
    public nonisolated let name: String
    public nonisolated let supportsTools: Bool = true

    private let client: APIClient

    /// - Parameters:
    ///   - client: configured `APIClient` (auth + retry already wired).
    ///   - name: stable identifier — typically `"remote.claude"` or
    ///     `"remote.gpt"`. The router pins on this string.
    public init(client: APIClient, name: String = "remote.claude") {
        self.client = client
        self.name = name
    }

    public func generate(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) async throws -> LLMResponse {
        // Phase 3 — build a `POST /api/llm/proxy` request with the
        // serialized prompt + tools array, await the response, and decode
        // into `LLMResponse`. For now we deliberately throw so the router
        // fallback path stays the only exercised one until the proxy
        // route lands server-side.
        _ = client
        throw LLMError.notImplemented
    }

    public nonisolated func stream(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMDelta, Error> {
        AsyncThrowingStream { continuation in
            // Phase 3 — open `POST /api/llm/proxy` with
            // `Accept: text/event-stream`, drain the body byte stream,
            // parse `data:` blocks per the shape documented at the top of
            // this file, and yield one `LLMDelta` per parsed event.
            continuation.finish(throwing: LLMError.notImplemented)
        }
    }
}
