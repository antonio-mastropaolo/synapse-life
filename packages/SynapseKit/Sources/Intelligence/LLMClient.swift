import Foundation

// MARK: - Errors

public enum LLMError: Error, Sendable, Equatable {
    case notImplemented
    case toolNotImplemented(String)
    case redactionFailed
    case transport
    case decoding
    case cancelled
}

// MARK: - Prompt / tools / responses

/// One message in the running conversation. Roles map 1:1 to what the
/// remote proxy expects (`system` | `user` | `assistant`).
public struct LLMMessage: Sendable, Hashable {
    public enum Role: String, Sendable, Hashable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// A single prompt sent to an `LLMClient`. We keep the system prompt
/// separate from `history` so the router can rewrite either without
/// having to splice arrays.
public struct LLMPrompt: Sendable, Hashable {
    public let system: String
    public let user: String
    public let history: [LLMMessage]

    public init(system: String, user: String, history: [LLMMessage] = []) {
        self.system = system
        self.user = user
        self.history = history
    }
}

/// JSON-Schema-flavored description of one tool the model may call. We
/// keep the schema as a string (the canonical JSON text) rather than a
/// typed nested struct so the wire shape sent to the remote proxy is
/// 100% under the caller's control; the model SDKs treat it as opaque
/// JSON anyway.
public struct LLMTool: Sendable, Hashable {
    public let name: String
    public let description: String
    /// JSON-Schema fragment describing the argument shape. e.g.
    /// `{"type":"object","properties":{"start":{"type":"string"}}}`.
    public let argsSchemaJSON: String

    public init(name: String, description: String, argsSchemaJSON: String) {
        self.name = name
        self.description = description
        self.argsSchemaJSON = argsSchemaJSON
    }
}

/// One tool invocation the model emitted. `arguments` is the raw JSON
/// object string as the model produced it; the tool registry parses
/// against the known schema for that tool name.
public struct LLMToolCall: Sendable, Hashable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Token accounting. Both fields are optional because not every client
/// (on-device especially) can report them.
public struct LLMUsage: Sendable, Hashable {
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// One-shot generate(...) response. `toolCalls` is empty when the model
/// just produced text.
public struct LLMResponse: Sendable, Hashable {
    public let text: String
    public let toolCalls: [LLMToolCall]
    public let usage: LLMUsage?

    public init(
        text: String,
        toolCalls: [LLMToolCall] = [],
        usage: LLMUsage? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

/// One incremental update from a streaming generation. The stream MUST
/// terminate with exactly one `.done(usage)` event so consumers can
/// observe end-of-stream without relying on `AsyncSequence` termination.
public enum LLMDelta: Sendable, Hashable {
    case text(String)
    case toolCall(LLMToolCall)
    case done(LLMUsage?)
}

// MARK: - Protocol

/// One pluggable LLM backend. Implementors are responsible for keeping
/// themselves `Sendable`; in practice everything in this module is an
/// `actor` so the constraint is free.
public protocol LLMClient: Sendable {
    /// Stable identifier the router and tests pin against. Conventional
    /// names: `"apple.foundation"`, `"remote.claude"`, `"remote.gpt"`,
    /// `"stub.always_ok"`.
    var name: String { get }

    /// `true` when this backend accepts the `tools:` array. The on-device
    /// model and remote proxies do; pure echo stubs typically don't.
    var supportsTools: Bool { get }

    func generate(prompt: LLMPrompt, tools: [LLMTool]) async throws -> LLMResponse

    /// Streaming variant. The returned stream is owned by the caller; the
    /// implementor MUST cancel any underlying network task when the
    /// stream is terminated.
    func stream(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMDelta, Error>
}
