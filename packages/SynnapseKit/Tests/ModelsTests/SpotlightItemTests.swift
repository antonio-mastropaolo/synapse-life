import Foundation
import Testing
@testable import Models

// Sample shaped from synapse-v2/app/api/spotlight/route.ts — the route returns
// { events: [ { id, messageId, kind, issueLabel, summary, runLink, paperUrl,
// overleafUrl, status, detectedAt, decidedAt, message: { ... } } ] }.
//
// We choose a SHIPPED candidate (status = "actioned") with run_link carrying
// the canonical top-candidate JSON the pipeline persists.
private let realisticServerJSON: String = """
{
  "events": [
    {
      "id": "evt-abc-123",
      "messageId": "msg-9f2a",
      "kind": "pick",
      "issueLabel": "ISSUE-2026-05-MAY",
      "summary": "Top candidate: Mutation Testing for LLM-Generated Code",
      "runLink": "{\\"kind\\":\\"pick\\",\\"candidates\\":[{\\"title\\":\\"Mutation Testing for LLM-Generated Code\\",\\"authors\\":[\\"A. Mastropaolo\\",\\"M. Lin\\"],\\"relevanceScore\\":0.91,\\"abstractUrl\\":\\"https://arxiv.org/abs/2505.01234\\",\\"pdfUrl\\":\\"https://arxiv.org/pdf/2505.01234.pdf\\",\\"venueTag\\":\\"TSE\\",\\"arxivId\\":\\"2505.01234\\"}]}",
      "paperUrl": "https://arxiv.org/abs/2505.01234",
      "overleafUrl": "https://www.overleaf.com/project/abc",
      "status": "actioned",
      "detectedAt": "2026-05-10T14:30:00.000Z",
      "decidedAt": "2026-05-11T09:00:00.000Z",
      "message": {
        "senderDisplay": "ArXiv Daily",
        "sender": "no-reply@arxiv.org",
        "subject": "Your daily arXiv digest",
        "receivedAt": "2026-05-10T14:00:00.000Z",
        "body": "See attached.",
        "threadId": "thr-7"
      }
    }
  ]
}
"""

private let minimalNullsJSON: String = """
{
  "events": [
    {
      "id": "evt-min",
      "messageId": "msg-min",
      "kind": "pick",
      "issueLabel": null,
      "summary": null,
      "runLink": null,
      "paperUrl": null,
      "overleafUrl": null,
      "status": "pending",
      "detectedAt": "2026-05-12T00:00:00.000Z",
      "decidedAt": null,
      "message": {
        "senderDisplay": "x",
        "sender": "x@y",
        "subject": "s",
        "receivedAt": "2026-05-12T00:00:00.000Z",
        "body": null,
        "threadId": null
      }
    }
  ]
}
"""

@Suite("SpotlightItem")
struct SpotlightItemTests {

    @Test
    func decodesRealisticServerJSON() throws {
        let data = try #require(realisticServerJSON.data(using: .utf8))
        let page = try JSONDecoder.synnapseSpotlight.decode(SpotlightPage.self, from: data)
        #expect(page.events.count == 1)

        let item = try #require(page.events.first)
        #expect(item.id == "evt-abc-123")
        #expect(item.messageId == "msg-9f2a")
        #expect(item.kind == "pick")
        #expect(item.issueLabel == "ISSUE-2026-05-MAY")
        #expect(item.summary == "Top candidate: Mutation Testing for LLM-Generated Code")
        #expect(item.status == "actioned")
        #expect(item.paperUrl?.absoluteString == "https://arxiv.org/abs/2505.01234")
        #expect(item.overleafUrl?.absoluteString == "https://www.overleaf.com/project/abc")
        #expect(item.message.subject == "Your daily arXiv digest")
        #expect(item.runLink != nil)

        // detectedAt round-trips as ISO-8601 with fractional seconds.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let detected = try #require(formatter.date(from: "2026-05-10T14:30:00.000Z"))
        #expect(item.detectedAt == detected)
    }

    @Test
    func decodesMinimalNullsWithoutCrashing() throws {
        let data = try #require(minimalNullsJSON.data(using: .utf8))
        let page = try JSONDecoder.synnapseSpotlight.decode(SpotlightPage.self, from: data)
        let item = try #require(page.events.first)
        #expect(item.issueLabel == nil)
        #expect(item.summary == nil)
        #expect(item.runLink == nil)
        #expect(item.paperUrl == nil)
        #expect(item.overleafUrl == nil)
        #expect(item.decidedAt == nil)
        #expect(item.message.body == nil)
        #expect(item.message.threadId == nil)
    }

    @Test
    func equatableAndHashableUseStableId() throws {
        let data = try #require(realisticServerJSON.data(using: .utf8))
        let a = try JSONDecoder.synnapseSpotlight.decode(SpotlightPage.self, from: data).events[0]
        let b = try JSONDecoder.synnapseSpotlight.decode(SpotlightPage.self, from: data).events[0]
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)

        var mutated = b
        mutated.status = "pending"
        // Equality is by id alone — the same id with different fields still
        // counts as the same logical item from the cache's perspective.
        #expect(a == mutated)
    }

    @Test
    func itemIsSendable() async throws {
        let data = try #require(realisticServerJSON.data(using: .utf8))
        let item = try JSONDecoder.synnapseSpotlight.decode(SpotlightPage.self, from: data).events[0]

        // Compile-time Sendable check via capture in a @Sendable closure.
        let job: @Sendable () -> String = { item.id }
        await Task.detached { _ = job() }.value
    }

    @Test
    func runLinkTopCandidateParses() throws {
        let data = try #require(realisticServerJSON.data(using: .utf8))
        let item = try JSONDecoder.synnapseSpotlight.decode(SpotlightPage.self, from: data).events[0]
        let top = try #require(item.topCandidate())
        #expect(top.title == "Mutation Testing for LLM-Generated Code")
        #expect(top.authors == ["A. Mastropaolo", "M. Lin"])
        #expect(top.venueTag == "TSE")
        #expect(top.pdfUrl?.absoluteString == "https://arxiv.org/pdf/2505.01234.pdf")
    }
}
