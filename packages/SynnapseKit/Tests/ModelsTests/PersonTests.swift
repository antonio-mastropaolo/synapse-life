import Foundation
import Testing
@testable import Models

/// Wire-level + projection tests for [[Person]] — the M7 People surface.
/// Mirrors the synapse-v2 `/api/senders` server contract (sender stats from
/// `lib/people.ts#listPeople`) and the dossier extension that includes
/// recent messages + open action items.
@Suite("Person / PersonDossier / Source decoding")
struct PersonTests {

    // MARK: - Person

    @Test
    func personDecodesFromNativeShape() throws {
        let json = """
        {
          "identity": "amastropaolo@wm.edu",
          "displayName": "Antonio Mastropaolo",
          "importanceWeight": 0.75,
          "autoBoost": 0.10,
          "effectiveWeight": 0.85,
          "blacklisted": false,
          "totalMessages": 412,
          "firstSeen": "2024-08-12T09:01:00Z",
          "lastSeen": "2026-05-15T14:30:00Z",
          "distinctThreads": 87,
          "awaitingMyReply": 3,
          "openActions": 5,
          "sources": ["gmail", "calendar"],
          "avgImportance": 0.62,
          "avatarUrl": "https://example.test/a.png",
          "avatarStatus": "found",
          "kind": "person"
        }
        """.data(using: .utf8)!

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let person = try dec.decode(Person.self, from: json)
        #expect(person.identity == "amastropaolo@wm.edu")
        #expect(person.displayName == "Antonio Mastropaolo")
        #expect(person.kind == .person)
        #expect(person.sources.contains(.gmail))
        #expect(person.sources.contains(.calendar))
        #expect(person.openActions == 5)
        #expect(person.awaitingMyReply == 3)
        #expect(person.avatarStatus == .found)
        #expect(person.avatarURL?.host == "example.test")
    }

    @Test
    func personFromSenderRowProjectsCleanly() {
        let row = ServerSenderRow(
            identity: "jled@wm.edu",
            displayName: "Jacqulyn Ledger",
            importanceWeight: 0.9,
            autoBoost: 0.0,
            effectiveWeight: 0.9,
            blacklisted: false,
            notes: "approver",
            totalMessages: 38,
            firstSeen: "2024-08-01T10:00:00Z",
            lastSeen: "2026-05-10T08:00:00Z",
            distinctThreads: 12,
            awaitingMyReply: 0,
            openActions: 2,
            sources: ["gmail", "outlook"],
            avgImportance: 0.55,
            avatarUrl: nil,
            avatarSource: nil,
            avatarStatus: "pending",
            avatarScore: nil,
            kindOverride: nil
        )
        let person = Person.fromServerRow(row)
        #expect(person.identity == "jled@wm.edu")
        #expect(person.sources == [.gmail, .outlook])
        #expect(person.notes == "approver")
        // No kindOverride → classification falls back to the heuristic
        // (real address shape, has display name → person).
        #expect(person.kind == .person)
    }

    @Test
    func personClassificationFallsBackToHeuristicWhenOverrideMissing() {
        // no-reply mailers project to .entity by heuristic.
        let row = ServerSenderRow(
            identity: "no-reply@stripe.com",
            displayName: "Stripe",
            importanceWeight: 0.1, autoBoost: 0.0, effectiveWeight: 0.1,
            blacklisted: false, notes: nil,
            totalMessages: 2, firstSeen: nil, lastSeen: nil,
            distinctThreads: 1, awaitingMyReply: 0, openActions: 0,
            sources: ["gmail"], avgImportance: 0.0,
            avatarUrl: nil, avatarSource: nil,
            avatarStatus: nil, avatarScore: nil,
            kindOverride: nil
        )
        let person = Person.fromServerRow(row)
        #expect(person.kind == .entity)
    }

    @Test
    func personManualKindOverrideWinsOverHeuristic() {
        // no-reply shape would heuristic to entity — but operator pinned it.
        let row = ServerSenderRow(
            identity: "no-reply@stripe.com",
            displayName: "Stripe",
            importanceWeight: 0.1, autoBoost: 0.0, effectiveWeight: 0.1,
            blacklisted: false, notes: nil,
            totalMessages: 2, firstSeen: nil, lastSeen: nil,
            distinctThreads: 1, awaitingMyReply: 0, openActions: 0,
            sources: ["gmail"], avgImportance: 0.0,
            avatarUrl: nil, avatarSource: nil,
            avatarStatus: nil, avatarScore: nil,
            kindOverride: "person"
        )
        let person = Person.fromServerRow(row)
        #expect(person.kind == .person)
    }

    @Test
    func personIsHashableByIdentity() {
        let a = Person(
            identity: "x@x.io", displayName: "A",
            importanceWeight: 0.5, autoBoost: 0.0, effectiveWeight: 0.5,
            blacklisted: false, notes: nil,
            totalMessages: 0, firstSeen: nil, lastSeen: nil,
            distinctThreads: 0, awaitingMyReply: 0, openActions: 0,
            sources: [], avgImportance: 0.0,
            avatarURL: nil, avatarStatus: nil, kind: .person
        )
        var b = a
        b = Person(
            identity: a.identity, displayName: "different label",
            importanceWeight: 0.9, autoBoost: 0.0, effectiveWeight: 0.9,
            blacklisted: false, notes: nil,
            totalMessages: 99, firstSeen: nil, lastSeen: nil,
            distinctThreads: 1, awaitingMyReply: 0, openActions: 0,
            sources: [.gmail], avgImportance: 0.0,
            avatarURL: nil, avatarStatus: nil, kind: .person
        )
        // Same identity → equal by id (identity-only equality).
        #expect(a == b)
        var s: Set<Person> = []
        s.insert(a); s.insert(b)
        #expect(s.count == 1)
    }

    // MARK: - Source forward-compat

    @Test
    func unknownSourceMapsToUnknown() throws {
        let raw = "\"slack-call\"".data(using: .utf8)!
        let s = try JSONDecoder().decode(Source.self, from: raw)
        #expect(s == .unknown)
    }

    // MARK: - PersonDossier merge

    @Test
    func dossierMergePreservesIdentityAndStacksMessages() {
        let base = Person(
            identity: "jled@wm.edu", displayName: "Jacqulyn Ledger",
            importanceWeight: 0.9, autoBoost: 0.0, effectiveWeight: 0.9,
            blacklisted: false, notes: nil,
            totalMessages: 38, firstSeen: nil, lastSeen: nil,
            distinctThreads: 12, awaitingMyReply: 0, openActions: 2,
            sources: [.gmail], avgImportance: 0.55,
            avatarURL: nil, avatarStatus: .pending, kind: .person
        )
        let recent = [
            DossierMessage(
                id: "m1", source: .gmail, subject: "FW: ATG",
                receivedAt: Date(timeIntervalSince1970: 1_730_000_000),
                category: "ai-tools", awaitingMyReply: false, rank: 0.8
            ),
            DossierMessage(
                id: "m2", source: .gmail, subject: nil,
                receivedAt: Date(timeIntervalSince1970: 1_731_000_000),
                category: nil, awaitingMyReply: true, rank: 0.6
            )
        ]
        let openItems = [
            DossierActionItem(id: "a1", text: "respond to Jacqulyn",
                              dueAt: nil, messageId: "m2",
                              messageSubject: nil)
        ]
        let dossier = PersonDossier(person: base, recentMessages: recent, openActionItems: openItems)
        #expect(dossier.person.identity == "jled@wm.edu")
        #expect(dossier.recentMessages.count == 2)
        #expect(dossier.openActionItems.count == 1)
    }
}
