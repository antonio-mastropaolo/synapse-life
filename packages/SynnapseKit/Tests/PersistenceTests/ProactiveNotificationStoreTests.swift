import Foundation
import Testing
@testable import Persistence
@testable import Models

/// Phase 4 — durable proactive feed. `ProactiveNotificationStore` mirrors
/// `ProactiveSignal` so a nightly analyzer pass dedups against persisted rows
/// instead of re-notifying. These tests pin the dedup, dismissal-survival,
/// ordering, and retention contracts.
@Suite("ProactiveNotificationStore")
struct ProactiveNotificationStoreTests {

    static let now = Date(timeIntervalSince1970: 1_779_840_000)

    private func makeStore() throws -> ProactiveNotificationStore {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return ProactiveNotificationStore(modelContainer: container)
    }

    private func signal(
        id: String,
        kind: ProactiveSignal.Kind = .anomalousSpend,
        headline: String = "Headline",
        body: String = "Body",
        date: Date = ProactiveNotificationStoreTests.now,
        severity: ProactiveSignal.Severity = .info
    ) -> ProactiveSignal {
        ProactiveSignal(
            id: id,
            kind: kind,
            headline: headline,
            body: body,
            subjectId: "subj-\(id)",
            date: date,
            severity: severity
        )
    }

    @Test
    func upsertRoundTripsAllFields() async throws {
        let store = try makeStore()
        let s = signal(id: "n1", kind: .upcomingBill, headline: "Bill", body: "Due soon", severity: .warning)
        _ = try await store.upsert(s, createdAt: Self.now)

        let read = try #require(try await store.get(id: "n1"))
        #expect(read.id == "n1")
        #expect(read.kind == .upcomingBill)
        #expect(read.headline == "Bill")
        #expect(read.body == "Due soon")
        #expect(read.subjectId == "subj-n1")
        #expect(read.severity == .warning)
    }

    @Test
    func reUpsertReportsChangedOnlyWhenContentDiffers() async throws {
        let store = try makeStore()
        _ = try await store.upsert(signal(id: "n1", body: "v1"), createdAt: Self.now)

        let unchanged = try await store.upsert(signal(id: "n1", body: "v1"), createdAt: Self.now)
        #expect(unchanged == false)

        let changed = try await store.upsert(signal(id: "n1", body: "v2"), createdAt: Self.now)
        #expect(changed == true)
        #expect(try await store.count() == 1)
    }

    @Test
    func dismissalSurvivesReUpsert() async throws {
        let store = try makeStore()
        _ = try await store.upsert(signal(id: "n1", body: "v1"), createdAt: Self.now)
        let didDismiss = try await store.setDismissed(id: "n1", true)
        #expect(didDismiss == true)

        // A nightly re-run upserts the same id with refreshed content. The
        // user's dismissal must not be undone, so it stays out of the default
        // feed even though its body was refreshed.
        _ = try await store.upsert(signal(id: "n1", body: "v2"), createdAt: Self.now)
        #expect(try await store.recent().contains { $0.id == "n1" } == false)
        let all = try await store.recent(includeDismissed: true)
        let row = try #require(all.first { $0.id == "n1" })
        #expect(row.body == "v2")
    }

    @Test
    func recentExcludesDismissedByDefaultAndRanksBySeverityThenDate() async throws {
        let store = try makeStore()
        let older = Self.now.addingTimeInterval(-3 * 86_400)
        _ = try await store.upsert(signal(id: "info-old", severity: .info), createdAt: older)
        _ = try await store.upsert(signal(id: "info-new", date: Self.now, severity: .info), createdAt: Self.now)
        _ = try await store.upsert(signal(id: "alert", severity: .alert), createdAt: Self.now)
        _ = try await store.upsert(signal(id: "dismissed", severity: .alert), createdAt: Self.now)
        _ = try await store.setDismissed(id: "dismissed", true)

        let visible = try await store.recent()
        #expect(visible.map(\.id) == ["alert", "info-new", "info-old"])

        let all = try await store.recent(includeDismissed: true)
        #expect(all.contains { $0.id == "dismissed" })
    }

    @Test
    func upsertAllReturnsNewOrChangedCount() async throws {
        let store = try makeStore()
        let first = try await store.upsertAll([
            signal(id: "a"), signal(id: "b"), signal(id: "c"),
        ], createdAt: Self.now)
        #expect(first == 3)

        // Re-run: b changes body, c+a identical, d is new -> 2 changed.
        let second = try await store.upsertAll([
            signal(id: "a"), signal(id: "b", body: "changed"), signal(id: "c"), signal(id: "d"),
        ], createdAt: Self.now)
        #expect(second == 2)
        #expect(try await store.count() == 4)
    }

    @Test
    func pruneDropsRowsOlderThanRetention() async throws {
        let store = try makeStore()
        let old = Self.now.addingTimeInterval(-40 * 86_400)
        _ = try await store.upsert(signal(id: "old"), createdAt: old)
        _ = try await store.upsert(signal(id: "fresh"), createdAt: Self.now)

        try await store.prune(olderThan: 30, now: Self.now)
        #expect(try await store.get(id: "old") == nil)
        #expect(try await store.get(id: "fresh") != nil)
    }
}
