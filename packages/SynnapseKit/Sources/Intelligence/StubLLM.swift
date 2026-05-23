import Foundation

/// Deterministic in-process LLM. Used by `IntelligenceTests`, by SwiftUI
/// previews, and by `LLMRouter` as the safety-net fallback when
/// `local` throws `LLMError.notImplemented` during Phase 3 development.
///
/// `generate(...)` returns `"stub: <user prompt>"`. `stream(...)` splits
/// that string on whitespace and yields one `.text(...)` delta per chunk,
/// closing with `.done(nil)`.
public actor StubLLM: LLMClient {
    public nonisolated let name: String = "stub.always_ok"
    public nonisolated let supportsTools: Bool = false

    public init() {}

    public func generate(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) async throws -> LLMResponse {
        LLMResponse(
            text: "stub: \(prompt.user)",
            toolCalls: [],
            usage: nil
        )
    }

    public nonisolated func stream(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMDelta, Error> {
        let text = "stub: \(prompt.user)"
        return AsyncThrowingStream { continuation in
            // Split on whitespace, preserving the separator in the
            // emitted chunk so re-concatenation reconstructs the source.
            let parts = text.split(
                separator: " ",
                omittingEmptySubsequences: false
            )
            for (i, part) in parts.enumerated() {
                let suffix = i == parts.count - 1 ? "" : " "
                continuation.yield(.text(String(part) + suffix))
            }
            continuation.yield(.done(nil))
            continuation.finish()
        }
    }
}
