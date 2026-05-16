import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

/// Network-level tests for the People surface. Mirrors `/api/senders` and
/// validates ETag/304 forward-compat (the server today emits no ETag, but the
/// client must tolerate one when the route adds it later).
@Suite("PeopleRepository")
struct PeopleRepositoryTests {

    private func sendersBody(rows: Int) -> Data {
        let senders: [[String: Any]] = (0..<rows).map { i in
            [
                "identity": "person-\(i)@wm.edu",
                "displayName": "Person \(i)",
                "importanceWeight": 0.5,
                "autoBoost": 0.0,
                "effectiveWeight": 0.5,
                "blacklisted": false,
                "notes": NSNull(),
                "totalMessages": 12 + i,
                "firstSeen": "2024-08-01T00:00:00Z",
                "lastSeen": "2026-05-15T14:00:00Z",
                "distinctThreads": 3,
                "awaitingMyReply": 0,
                "openActions": 0,
                "sources": ["gmail"],
                "avgImportance": 0.3,
                "avatarUrl": NSNull(),
                "avatarSource": NSNull(),
                "avatarStatus": NSNull(),
                "avatarScore": NSNull(),
                "kindOverride": NSNull()
            ]
        }
        return try! JSONSerialization.data(withJSONObject: ["senders": senders])
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

    @Test
    func listFetchProjectsServerRows() async throws {
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.hasSuffix("/api/senders") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json", "ETag": "\"p-v1\""],
                body: self.sendersBody(rows: 3)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LivePeopleAPI(client: makeClient(session: session))
        let repo = PeopleRepository(api: api)
        try await repo.refresh()
        let people = await repo.people
        #expect(people.count == 3)
        #expect(people.first?.identity == "person-0@wm.edu")
    }

    @Test
    func cacheSurvives304() async throws {
        let counter = PeopleAtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            if n == 1 {
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json", "ETag": "\"p-1\""],
                    body: self.sendersBody(rows: 1)
                ))
            }
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"p-1\"")
            return .success(.init(statusCode: 304, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LivePeopleAPI(client: makeClient(session: session))
        let repo = PeopleRepository(api: api)
        try await repo.refresh()
        #expect(await repo.people.count == 1)
        try await repo.refresh()
        // 304 path returns no payload — repository preserves the cached list.
        #expect(await repo.people.count == 1)
        #expect(await repo.people.first?.identity == "person-0@wm.edu")
    }

    @Test
    func dossierFetchProjectsDossierEnvelope() async throws {
        let dossierBody: [String: Any] = [
            "identity": "jled@wm.edu",
            "displayName": "Jacqulyn Ledger",
            "importanceWeight": 0.9, "autoBoost": 0.0, "effectiveWeight": 0.9,
            "blacklisted": false, "notes": NSNull(),
            "totalMessages": 38, "firstSeen": "2024-08-01T00:00:00Z",
            "lastSeen": "2026-05-15T14:00:00Z",
            "distinctThreads": 12, "awaitingMyReply": 0, "openActions": 2,
            "sources": ["gmail"], "avgImportance": 0.55,
            "avatarUrl": NSNull(), "avatarSource": NSNull(),
            "avatarStatus": NSNull(), "avatarScore": NSNull(),
            "kindOverride": NSNull(),
            "recentMessages": [
                [
                    "id": "m1", "source": "gmail",
                    "subject": "FW: ATG",
                    "body": "...",
                    "receivedAt": "2026-05-10T08:00:00Z",
                    "category": "ai-tools",
                    "awaitingMyReply": false,
                    "rank": 0.8
                ]
            ],
            "openActionItems": [
                [
                    "id": "a1", "text": "respond to Jacqulyn",
                    "dueAt": NSNull(),
                    "messageId": "m2",
                    "messageSubject": NSNull()
                ]
            ],
            "categoryMix": ["ai-tools": 12]
        ]
        let data = try JSONSerialization.data(withJSONObject: dossierBody)
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.contains("/api/senders/") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: data
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LivePeopleAPI(client: makeClient(session: session))
        let dossier = try await api.dossier(for: "jled@wm.edu")
        #expect(dossier.person.identity == "jled@wm.edu")
        #expect(dossier.recentMessages.count == 1)
        #expect(dossier.openActionItems.count == 1)
    }
}

// File-private synchronization helper. Cannot share AtomicInt with sibling
// test files (each is file-private to its own).
final class PeopleAtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var n: Int = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}
