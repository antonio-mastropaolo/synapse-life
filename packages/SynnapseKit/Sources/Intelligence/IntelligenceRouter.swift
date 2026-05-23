import Foundation

/// Decides whether a given prompt is answered on-device (Apple
/// FoundationModels) or remotely (Claude/GPT via our proxy), and runs
/// the prompt through the PII redactor on the remote path.
///
/// ## Routing rule (Phase 3 starting point)
///
/// A query is "simple" — and therefore routed to `local` — when **both**
/// of these hold:
///
/// * `prompt.user.count < 200`
/// * `tools.count <= 2`
///
/// Anything else is "complex" and routed to `remote`. Remote-bound
/// prompts are redacted via `PIIRedactor.redact(...)` first; the
/// resulting `LLMPrompt` has the same system message and history but the
/// `user` field carries the scrubbed text.
///
/// On `LLMError.notImplemented` from `local` (which is the steady-state
/// during Phase 3 dev, before the real FoundationModels call lands), we
/// fall through to `StubLLM` so the UI doesn't break.
///
/// TODO(phase3): tune the simple/complex threshold from telemetry once
/// we have it. The 200-character cut-off is a guess.
public actor IntelligenceRouter {
    private let local: any LLMClient
    private let remote: any LLMClient
    private let redactor: PIIRedactor
    private let fallback: any LLMClient

    public init(
        local: any LLMClient,
        remote: any LLMClient,
        redactor: PIIRedactor,
        fallback: any LLMClient = StubLLM()
    ) {
        self.local = local
        self.remote = remote
        self.redactor = redactor
        self.fallback = fallback
    }

    public func route(
        _ prompt: LLMPrompt,
        tools: [LLMTool]
    ) async throws -> LLMResponse {
        if Self.isSimple(prompt: prompt, tools: tools) {
            do {
                return try await local.generate(prompt: prompt, tools: tools)
            } catch LLMError.notImplemented {
                // Steady-state during Phase 3 dev: local backend is a
                // shell. Fall back to the deterministic stub so the UI
                // keeps painting.
                return try await fallback.generate(prompt: prompt, tools: tools)
            }
        } else {
            let redactedUser = redactor.redact(prompt.user)
            let redactedPrompt = LLMPrompt(
                system: prompt.system,
                user: redactedUser,
                history: prompt.history
            )
            return try await remote.generate(prompt: redactedPrompt, tools: tools)
        }
    }

    /// Routing predicate. Pulled out as a static so tests can assert
    /// against it without spinning up a full router.
    public static func isSimple(prompt: LLMPrompt, tools: [LLMTool]) -> Bool {
        prompt.user.count < 200 && tools.count <= 2
    }
}
