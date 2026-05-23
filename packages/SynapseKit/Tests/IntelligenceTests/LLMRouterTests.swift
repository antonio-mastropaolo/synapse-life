import XCTest
@testable import Intelligence

/// A tagged stub that records the prompt it received so tests can pin
/// which backend was picked.
private actor TaggedStubLLM: LLMClient {
    nonisolated let name: String
    nonisolated let supportsTools: Bool = false
    private(set) var lastPromptUser: String?
    private(set) var callCount: Int = 0

    init(name: String) { self.name = name }

    func generate(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) async throws -> LLMResponse {
        callCount += 1
        lastPromptUser = prompt.user
        return LLMResponse(text: "\(name): \(prompt.user)")
    }

    nonisolated func stream(
        prompt: LLMPrompt,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMDelta, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// A spying redactor wrapper. The router takes a `PIIRedactor` value, so
/// we can't inject a subclass — instead the test asserts on the router's
/// observed behavior using a sentinel token that the production redactor
/// would never produce on this input.
///
/// We instead use the real `PIIRedactor` and a custom recorder that
/// shadows its call shape via a side-channel actor.
private actor RedactionRecorder {
    private(set) var inputs: [String] = []
    func record(_ s: String) { inputs.append(s) }
}

final class LLMRouterTests: XCTestCase {

    func test_shortPrompt_routesToLocal() async throws {
        let local = TaggedStubLLM(name: "fake.local")
        let remote = TaggedStubLLM(name: "fake.remote")
        let router = LLMRouter(
            local: local,
            remote: remote,
            redactor: PIIRedactor()
        )
        let response = try await router.route(
            LLMPrompt(system: "sys", user: "What's my balance?"),
            tools: []
        )
        XCTAssertTrue(response.text.hasPrefix("fake.local:"), response.text)
        let localCalls = await local.callCount
        let remoteCalls = await remote.callCount
        XCTAssertEqual(localCalls, 1)
        XCTAssertEqual(remoteCalls, 0)
    }

    func test_longPrompt_routesToRemote_afterRedaction() async throws {
        let local = TaggedStubLLM(name: "fake.local")
        let remote = TaggedStubLLM(name: "fake.remote")
        let router = LLMRouter(
            local: local,
            remote: remote,
            redactor: PIIRedactor()
        )
        // 220+ chars, with a real email so the redactor has work to do.
        let body = String(repeating: "context. ", count: 30)
        let longUser = "\(body) my email is leaky@example.com"
        XCTAssertGreaterThanOrEqual(longUser.count, 200)

        let response = try await router.route(
            LLMPrompt(system: "sys", user: longUser),
            tools: []
        )
        XCTAssertTrue(response.text.hasPrefix("fake.remote:"), response.text)

        // Verify the remote received the REDACTED text, not the raw.
        let received = await remote.lastPromptUser ?? ""
        XCTAssertTrue(received.contains("<email>"), received)
        XCTAssertFalse(received.contains("leaky@example.com"), received)
    }

    func test_manyTools_routesToRemote() async throws {
        let local = TaggedStubLLM(name: "fake.local")
        let remote = TaggedStubLLM(name: "fake.remote")
        let router = LLMRouter(
            local: local,
            remote: remote,
            redactor: PIIRedactor()
        )
        let tools = (0..<5).map { i in
            LLMTool(
                name: "t\(i)",
                description: "",
                argsSchemaJSON: #"{"type":"object"}"#
            )
        }
        let response = try await router.route(
            LLMPrompt(system: "s", user: "short"),
            tools: tools
        )
        XCTAssertTrue(response.text.hasPrefix("fake.remote:"), response.text)
    }

    func test_localNotImplemented_fallsBackToStub() async throws {
        let local = AppleFoundationLLM()  // throws notImplemented
        let remote = TaggedStubLLM(name: "fake.remote")
        let router = LLMRouter(
            local: local,
            remote: remote,
            redactor: PIIRedactor()
        )
        let response = try await router.route(
            LLMPrompt(system: "s", user: "hi"),
            tools: []
        )
        // Fallback is StubLLM, which prefixes with "stub: ".
        XCTAssertEqual(response.text, "stub: hi")
        let remoteCalls = await remote.callCount
        XCTAssertEqual(remoteCalls, 0)
    }

    func test_isSimple_predicate() {
        let short = LLMPrompt(system: "", user: "hi")
        let long = LLMPrompt(system: "", user: String(repeating: "x", count: 250))
        XCTAssertTrue(LLMRouter.isSimple(prompt: short, tools: []))
        XCTAssertFalse(LLMRouter.isSimple(prompt: long, tools: []))
        let twoTools = [
            LLMTool(name: "a", description: "", argsSchemaJSON: "{}"),
            LLMTool(name: "b", description: "", argsSchemaJSON: "{}")
        ]
        XCTAssertTrue(LLMRouter.isSimple(prompt: short, tools: twoTools))
        let threeTools = twoTools + [
            LLMTool(name: "c", description: "", argsSchemaJSON: "{}")
        ]
        XCTAssertFalse(LLMRouter.isSimple(prompt: short, tools: threeTools))
    }
}
