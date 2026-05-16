import Foundation
import Testing
@testable import Models
@testable import Networking

private func advisorsListBody() -> Data {
    let payload: [String: Any] = [
        "advisors": [
            [
                "id": "financial",
                "name": "Wealth Coach",
                "specialty": "Budgets & cash flow",
                "avatarColor": "#34d399",
                "avatarInitials": "WC",
                "unreadCount": 2,
                "lastThreadId": "thr_001",
                "lastSummary": "Reviewed sub renewals",
                "lastActiveAt": 1_715_798_400_000
            ],
            [
                "id": "grant",
                "name": "Grant Advisor",
                "specialty": "NSF & university budgets",
                "avatarColor": "#60a5fa",
                "avatarInitials": "GA",
                "unreadCount": 0,
                "lastThreadId": NSNull(),
                "lastSummary": NSNull(),
                "lastActiveAt": NSNull()
            ]
        ]
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private func sseStream(_ deltas: [String]) -> Data {
    // Each line block: `data: ...\n\n`
    let joined = deltas.map { "data: \($0)\n\n" }.joined()
    return joined.data(using: .utf8)!
}

private func makeClient(session: URLSession) -> APIClient {
    APIClient(
        baseURL: URL(string: "https://api.synnapse.test/v1/")!,
        session: session,
        defaultHeaders: ["Accept": "application/json"],
        auth: nil,
        retry: .none
    )
}

@Suite("AdvisorsRepository")
struct AdvisorsRepositoryTests {

    @Test
    func listDecodesAdvisorsEnvelope() async throws {
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.hasSuffix("/api/ai-advisors") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: advisorsListBody()
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveAdvisorsAPI(client: makeClient(session: session))
        let advisors = try await api.list()
        #expect(advisors.count == 2)
        #expect(advisors[0].id == "financial")
        #expect(advisors[0].unreadCount == 2)
        #expect(advisors[1].lastThreadId == nil)
    }

    @Test
    func listSurfacesServerErrorAsTypedAPIError() async throws {
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(statusCode: 500, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveAdvisorsAPI(client: makeClient(session: session))
        do {
            _ = try await api.list()
            Issue.record("expected throw")
        } catch let APIError.server(status) {
            #expect(status == 500)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func streamChatYieldsTextDeltasThenDone() async throws {
        let body = sseStream([
            #"{"text":"Hello"}"#,
            #"{"text":", "}"#,
            #"{"text":"world"}"#,
            #"{"done":true,"threadId":"thr_42"}"#
        ])
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.hasSuffix("/api/ai-advisors/financial/chat") == true)
            #expect(request.httpMethod == "POST")
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveAdvisorsAPI(client: makeClient(session: session))
        let stream = api.streamChat(
            advisorId: "financial",
            userMessage: "what's my burn?",
            threadId: nil
        )
        var collected: [ChatDelta] = []
        for try await delta in stream {
            collected.append(delta)
        }
        #expect(collected.count == 4)
        if case let .text(t) = collected[0] { #expect(t == "Hello") }
        if case let .done(threadId) = collected[3] {
            #expect(threadId == "thr_42")
        } else {
            Issue.record("expected done at index 3, got \(collected[3])")
        }
    }

    @Test
    func streamChatSurfacesErrorDelta() async throws {
        let body = sseStream([#"{"error":"rate limit"}"#])
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveAdvisorsAPI(client: makeClient(session: session))
        var sawError: String?
        for try await delta in api.streamChat(advisorId: "x", userMessage: "y", threadId: nil) {
            if case let .error(msg) = delta { sawError = msg }
        }
        #expect(sawError == "rate limit")
    }
}

@Suite("SSEParser")
struct SSEParserTests {

    @Test func parsesTextEvent() {
        let block = "data: {\"text\":\"hi\"}\n"
        let delta = SSEParser.parseDataBlock(block)
        #expect(delta == .text("hi"))
    }

    @Test func parsesDoneEvent() {
        let block = "data: {\"done\":true,\"threadId\":\"thr_1\"}\n"
        let delta = SSEParser.parseDataBlock(block)
        #expect(delta == .done(threadId: "thr_1"))
    }

    @Test func ignoresNonDataLines() {
        let block = ": heartbeat\n"
        #expect(SSEParser.parseDataBlock(block) == nil)
    }

    @Test func returnsNilForEmptyOrInvalidJSON() {
        #expect(SSEParser.parseDataBlock("") == nil)
        #expect(SSEParser.parseDataBlock("data: not-json\n") == nil)
        // Recognised shape but no fields → nil.
        #expect(SSEParser.parseDataBlock("data: {}\n") == nil)
    }
}
