import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM client backed by Apple's `FoundationModels` framework
/// (iOS 18.1+ / macOS 15.1+). This class is intentionally a shell — Phase
/// 3 of the plan wires in the real `SystemLanguageModel.shared.respond(...)`
/// call. For now both `generate` and `stream` throw
/// `LLMError.notImplemented` so the router fallback path is exercised.
///
/// The actor isolation gives us a serialization point for the on-device
/// session (FoundationModels sessions aren't safe to use from multiple
/// concurrent contexts).
public actor AppleFoundationLLM: LLMClient {
    public nonisolated let name: String = "apple.foundation"
    public nonisolated let supportsTools: Bool = true

    public init() {}

    public func generate(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) async throws -> LLMResponse {
        #if canImport(FoundationModels)
        // Phase 3 — call SystemLanguageModel.shared.respond(...) here,
        // translating `prompt`/`tools` into the FoundationModels session
        // shape and folding the response back into `LLMResponse`.
        throw LLMError.notImplemented
        #else
        throw LLMError.notImplemented
        #endif
    }

    public nonisolated func stream(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMDelta, Error> {
        AsyncThrowingStream { continuation in
            // Phase 3 — open a FoundationModels streaming session here
            // and forward token deltas + tool-call events.
            continuation.finish(throwing: LLMError.notImplemented)
        }
    }
}
