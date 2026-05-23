import Foundation

/// `Intelligence` is the hybrid LLM substrate for Synnapse.
///
/// ## Routing strategy (Phase 3)
///
/// The app needs two qualitatively different "thinking" surfaces:
///
/// * **On-device (Apple FoundationModels, iOS 18.1+).** Routine work:
///   category suggestions, short rephrasings, simple structured tool calls
///   against the local SwiftData store. Cheap, private, offline-capable.
/// * **Remote (Claude / GPT via our `/api/llm/proxy` SSE endpoint).** Hard
///   Q&A and long-form narrative. Expensive, requires network, never sees
///   raw PII because the request goes through `PIIRedactor` first.
///
/// `IntelligenceRouter` makes the local-vs-remote choice based on prompt
/// shape (length + tool count for now; will be re-tuned from telemetry in
/// Phase 3). When the router decides "remote", it MUST first run the
/// prompt through `PIIRedactor.redact(_:allowedMerchants:)`. The redactor
/// is the only place this module currently ships real, production-shaped
/// logic — every other type is a typed surface waiting for Phase 3 to
/// fill in the model-call internals.
///
/// ## PII redaction contract
///
/// `PIIRedactor` removes account numbers, card numbers, emails, phones,
/// SSNs, addresses, dollar amounts above a configurable threshold, and
/// merchant strings that aren't explicitly whitelisted. The contract is
/// **conservative**: when in doubt, redact. A leaked merchant is a worse
/// outcome than a slightly less specific LLM answer.
///
/// Tests live at `Tests/IntelligenceTests/PIIRedactorTests.swift` and lock
/// the exact substitution shape, including the "$49,999 stays, $50,001
/// redacts" threshold boundary.
public enum IntelligenceModule {
    /// Schema version for the prompt/tool/delta types defined here. Bump
    /// the minor when adding a non-breaking field, the major when changing
    /// the wire shape the remote proxy consumes.
    public static let schemaVersion: String = "0.1.0"
}
