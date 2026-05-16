import Foundation
import Testing
@testable import Models
@testable import Networking

@Suite("LiveSequencesAPI")
struct LiveSequencesAPITests {

    private func makeClient(handler: @escaping URLProtocolStub.Handler) async -> (APIClient, URLSession) {
        let session = URLProtocolStub.makeSession(handler)
        let client = APIClient(
            baseURL: URL(string: "https://example.test/")!,
            session: session
        )
        return (client, session)
    }

    @Test
    func decodesAListPage() async throws {
        let body = """
        {
          "total": 2,
          "sequences": [
            {
              "id": "seq-1",
              "opportunity_id": "opp-1",
              "lead_email": "a@x.com",
              "lead_display": "A",
              "subject": "S1",
              "touch1_body": "B1",
              "current_touch": 1,
              "last_sent_at": 1739625600.0,
              "next_due_at": 1739712000.0,
              "status": "active",
              "last_log": null,
              "created_at": 1739625500.0
            },
            {
              "id": "seq-2",
              "opportunity_id": "opp-2",
              "lead_email": "b@x.com",
              "lead_display": "B",
              "subject": "S2",
              "touch1_body": "B2",
              "current_touch": 0,
              "last_sent_at": null,
              "next_due_at": 1739725000.0,
              "status": "paused",
              "last_log": "queued",
              "created_at": 1739625400.0
            }
          ]
        }
        """.data(using: .utf8)!

        let (client, session) = await makeClient { _ in
            .success(URLProtocolStub.Response(
                statusCode: 200,
                headers: ["ETag": "\"abc\"", "Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSequencesAPI(client: client)
        let resp = try await api.list(status: .active, ifNoneMatch: nil)
        #expect(resp.notModified == false)
        #expect(resp.total == 2)
        #expect(resp.etag == "\"abc\"")
        #expect(resp.sequences.count == 2)
        #expect(resp.sequences[0].status == .active)
        #expect(resp.sequences[1].status == .paused)
    }

    @Test
    func sendsIfNoneMatchAndHandles304() async throws {
        let (client, session) = await makeClient { request in
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"prev\"")
            return .success(URLProtocolStub.Response(
                statusCode: 304,
                headers: ["ETag": "\"prev\""]
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSequencesAPI(client: client)
        let resp = try await api.list(status: .active, ifNoneMatch: "\"prev\"")
        #expect(resp.notModified)
        #expect(resp.sequences.isEmpty)
        #expect(resp.etag == "\"prev\"")
    }

    @Test
    func upsertDraftEchoesBackWhenServerContractIsOff() async throws {
        let (client, session) = await makeClient { _ in
            // Should never be called — server contract is off.
            .success(URLProtocolStub.Response(statusCode: 500))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSequencesAPI(client: client, serverDraftContractLive: false)
        let delta = StageDraftDelta(
            sequenceId: "seq-1",
            stageId: "seq-1#2",
            subject: "Follow-up",
            body: "Hi again."
        )
        let echoed = try await api.upsertDraft(delta)
        #expect(echoed == delta)

        // The 500-response handler must NOT have been hit.
        let recorded = URLProtocolStub.requests(for: session)
        #expect(recorded.isEmpty)
    }

    @Test
    func upsertDraftHitsServerWhenContractIsLive() async throws {
        let (client, session) = await makeClient { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path.hasSuffix("/api/sequences/seq-1/stages/seq-1#2") == true)
            let body = """
            {
              "sequenceId": "seq-1",
              "stageId": "seq-1#2",
              "subject": "Echoed",
              "body": "Echoed body"
            }
            """.data(using: .utf8)!
            return .success(URLProtocolStub.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSequencesAPI(client: client, serverDraftContractLive: true)
        let delta = StageDraftDelta(
            sequenceId: "seq-1",
            stageId: "seq-1#2",
            subject: "Original",
            body: "Original body"
        )
        let echoed = try await api.upsertDraft(delta)
        #expect(echoed.subject == "Echoed")
        #expect(echoed.body == "Echoed body")
    }

    @Test
    func getByIdFiltersTheListWhenServerHasNoDetailEndpoint() async throws {
        let body = """
        {
          "total": 2,
          "sequences": [
            {
              "id": "seq-A",
              "opportunity_id": "o-A",
              "lead_email": "a@x.com",
              "lead_display": "A",
              "subject": "SA",
              "touch1_body": "BA",
              "current_touch": 1,
              "last_sent_at": 1739625600.0,
              "next_due_at": null,
              "status": "active",
              "last_log": null,
              "created_at": 1739625500.0
            },
            {
              "id": "seq-B",
              "opportunity_id": "o-B",
              "lead_email": "b@x.com",
              "lead_display": "B",
              "subject": "SB",
              "touch1_body": "BB",
              "current_touch": 0,
              "last_sent_at": null,
              "next_due_at": null,
              "status": "active",
              "last_log": null,
              "created_at": 1739625400.0
            }
          ]
        }
        """.data(using: .utf8)!
        let (client, session) = await makeClient { _ in
            .success(URLProtocolStub.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveSequencesAPI(client: client)
        let found = try await api.get(id: "seq-B")
        #expect(found?.id == "seq-B")
        let missing = try await api.get(id: "seq-Z")
        #expect(missing == nil)
    }
}

@Suite("MockSequencesAPI")
struct MockSequencesAPITests {
    @Test
    func roundTripsListAndUpsert() async throws {
        let mock = MockSequencesAPI()
        let seq = Sequence(
            id: "s1", opportunityId: "o1", leadEmail: "x@y.com",
            leadDisplay: "X", subject: "S",
            stages: [SequenceStage(
                id: "s1#1", touchNumber: 1, dayOffset: 0,
                channel: .email, subject: "S", body: "B", status: .sent
            )],
            currentTouch: 1,
            lastSentAt: nil, nextDueAt: nil, status: .active,
            lastLog: nil, createdAt: Date(timeIntervalSince1970: 0)
        )
        await mock.setNextList([seq], etag: "\"e\"")
        let listed = try await mock.list(status: .active, ifNoneMatch: nil)
        #expect(listed.sequences.count == 1)
        #expect(listed.etag == "\"e\"")
        #expect(await mock.listCallCount == 1)

        let delta = StageDraftDelta(sequenceId: "s1", stageId: "s1#1", subject: "S2", body: "B2")
        _ = try await mock.upsertDraft(delta)
        #expect(await mock.upsertCallCount == 1)
        #expect(await mock.lastUpsertDelta == delta)
    }
}
