import Foundation
import Testing
@testable import Models

/// Wire-level tests for [[InboxItem]] — the M7 Inbox surface. Mirrors the
/// synapse-v2 `/api/messages` route handler. Inbox is READ-ONLY in M7; the
/// `read` flag is a client-side projection (server has no `read` column yet)
/// but the type carries it so optimistic mark-read tests can drive it.
@Suite("InboxItem / SourceFolder decoding")
struct InboxItemTests {

    @Test
    func inboxItemDecodesFromMessagesEnvelope() throws {
        let json = """
        {
          "total": 2,
          "messages": [
            {
              "id": "m-1",
              "source": "gmail",
              "externalId": "abc",
              "threadId": "t-1",
              "sender": "jled@wm.edu",
              "senderDisplay": "Jacqulyn Ledger",
              "recipients": ["amastropaolo@wm.edu"],
              "subject": "Re: Anthropic spend",
              "body": "Looks good. Approved.",
              "receivedAt": "2026-05-15T14:30:00.000Z",
              "createdAt": "2026-05-15T14:30:00.000Z",
              "insight": null,
              "actionItems": []
            },
            {
              "id": "m-2",
              "source": "outlook",
              "externalId": "def",
              "threadId": null,
              "sender": "no-reply@stripe.com",
              "senderDisplay": "Stripe",
              "recipients": ["amastro1996@gmail.com"],
              "subject": null,
              "body": "Receipt attached.",
              "receivedAt": "2026-05-15T13:00:00Z",
              "createdAt": "2026-05-15T13:00:00Z",
              "insight": null,
              "actionItems": []
            }
          ]
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder.synnapseInbox.decode(InboxPage.self, from: json)
        #expect(envelope.total == 2)
        #expect(envelope.items.count == 2)
        let first = envelope.items[0]
        #expect(first.id == "m-1")
        #expect(first.source == .gmail)
        #expect(first.subject == "Re: Anthropic spend")
        #expect(first.threadId == "t-1")
        // Inbox items start as unread until the operator marks them read.
        #expect(first.isRead == false)
        let second = envelope.items[1]
        // Missing fractional seconds — must still decode (matches receivedAt
        // strategy used by [[SpotlightItem]]).
        #expect(second.source == .outlook)
        #expect(second.subject == nil)
    }

    @Test
    func subjectFallsBackToBodySnippetWhenSubjectMissing() {
        let item = InboxItem(
            id: "x", source: .gmail, threadId: nil,
            sender: "x@x.io", senderDisplay: "X",
            subject: nil, body: "First line of body content here.",
            bodyPreview: "First line of body content here.",
            receivedAt: Date(timeIntervalSince1970: 1_730_000_000),
            isRead: false
        )
        #expect(item.displaySubject == "First line of body content here.")
    }

    @Test
    func displaySubjectPrefersExplicitSubject() {
        let item = InboxItem(
            id: "x", source: .gmail, threadId: nil,
            sender: "x@x.io", senderDisplay: "X",
            subject: "Explicit subject",
            body: "Body content",
            bodyPreview: "Body content",
            receivedAt: Date(timeIntervalSince1970: 1_730_000_000),
            isRead: false
        )
        #expect(item.displaySubject == "Explicit subject")
    }

    @Test
    func unknownSourceDoesNotPoisonDecode() throws {
        let json = """
        {
          "total": 1,
          "messages": [
            {
              "id": "m-x",
              "source": "carrier-pigeon",
              "externalId": "xx",
              "threadId": null,
              "sender": "x@x.io",
              "senderDisplay": "X",
              "recipients": [],
              "subject": "Hi",
              "body": "Hello",
              "receivedAt": "2026-05-15T14:30:00Z",
              "createdAt": "2026-05-15T14:30:00Z",
              "insight": null,
              "actionItems": []
            }
          ]
        }
        """.data(using: .utf8)!
        let page = try JSONDecoder.synnapseInbox.decode(InboxPage.self, from: json)
        #expect(page.items.first?.source == .unknown)
    }

    @Test
    func inboxItemHashableByIdAlone() {
        let a = InboxItem(
            id: "same", source: .gmail, threadId: nil,
            sender: "x@x.io", senderDisplay: "X",
            subject: "A", body: "A", bodyPreview: "A",
            receivedAt: Date(), isRead: false
        )
        var b = a
        b = InboxItem(
            id: "same", source: .gmail, threadId: nil,
            sender: "x@x.io", senderDisplay: "X",
            subject: "Different label", body: "Different body",
            bodyPreview: "Different",
            receivedAt: Date(timeIntervalSince1970: 0),
            isRead: true
        )
        #expect(a == b)
        var s = Set<InboxItem>(); s.insert(a); s.insert(b)
        #expect(s.count == 1)
    }

    @Test
    func sourceFolderEnumCoversAllSources() {
        let all = SourceFolder.allCases.map(\.source)
        // Every source the messages route emits must round-trip to a folder.
        for s in [Source.gmail, .calendar, .slack, .outlook, .discord, .pipeline] {
            #expect(all.contains(s), "no folder maps to \(s)")
        }
    }
}
