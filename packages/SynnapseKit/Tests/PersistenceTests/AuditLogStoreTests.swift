import Foundation
import Testing
import SwiftData
@testable import Persistence

/// Append-only / newest-first / forward-compat contract for `AuditLogStore`.
@Suite("AuditLogStore")
struct AuditLogStoreTests {

    private func makeStoreAndContainer() throws -> (AuditLogStore, ModelContainer) {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return (AuditLogStore(modelContainer: container), container)
    }

    @Test
    func appendsAndRecentReturnsNewestFirst() async throws {
        let (store, _) = try makeStoreAndContainer()
        // Stagger timestamps so newest-first ordering is observable.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let kinds: [AuditEventKind] = [.piiRead, .plaidLink, .transactionSync, .llmCall, .auth]
        for (i, kind) in kinds.enumerated() {
            try await store.append(
                kind: kind,
                subject: "subject-\(i)",
                detail: "detail-\(i)",
                outcome: .ok,
                timestamp: base.addingTimeInterval(Double(i) * 60)
            )
        }
        let recent = try await store.recent(limit: 10)
        #expect(recent.count == 5)
        // newest first → reverse of insertion order.
        #expect(recent.map(\.subject) == ["subject-4", "subject-3", "subject-2", "subject-1", "subject-0"])
        // The typed enum projection survives for known raw values.
        #expect(recent.first?.kind == .auth)
        #expect(recent.last?.kind == .piiRead)
    }

    @Test
    func pruneOlderThanDeletesOldRows() async throws {
        let (store, _) = try makeStoreAndContainer()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oneDay: TimeInterval = 86_400

        // 3 ancient (60d old) + 2 fresh (1d old).
        for i in 0..<3 {
            try await store.append(
                kind: .piiRead,
                subject: "old-\(i)",
                detail: nil,
                outcome: .ok,
                timestamp: now.addingTimeInterval(-60 * oneDay)
            )
        }
        for i in 0..<2 {
            try await store.append(
                kind: .piiRead,
                subject: "fresh-\(i)",
                detail: nil,
                outcome: .ok,
                timestamp: now.addingTimeInterval(-oneDay)
            )
        }
        #expect(try await store.count() == 5)

        try await store.prune(olderThan: 30, now: now)
        let remaining = try await store.recent(limit: 100)
        #expect(remaining.count == 2)
        #expect(remaining.allSatisfy { $0.subject.hasPrefix("fresh-") })
    }

    @Test
    func unknownKindRawRoundTripsButKindIsNil() async throws {
        let (store, container) = try makeStoreAndContainer()
        // We can't reach an unknown raw value through the typed `append`
        // surface — so we write straight to a context backed by the same
        // container the store sees. This simulates a row written by a
        // future binary that introduced a new `AuditEventKind` case.
        let context = ModelContext(container)
        context.insert(PersistedAuditLog(
            id: "future-1",
            timestamp: Date(),
            kindRaw: "future.kind",
            subject: "subj",
            detail: nil,
            outcome: "ok"
        ))
        try context.save()

        let recent = try await store.recent(limit: 10)
        let row = try #require(recent.first { $0.id == "future-1" })
        // The raw string survives verbatim...
        #expect(row.kindRaw == "future.kind")
        // ...but the typed projection is nil because this binary doesn't
        // know the case yet. This is the forward-compat contract.
        #expect(row.kind == nil)
    }
}
