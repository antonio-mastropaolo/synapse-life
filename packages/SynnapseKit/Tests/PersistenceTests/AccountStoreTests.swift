import Foundation
import Testing
import SwiftData
@testable import Persistence
@testable import Models

/// Round-trip + change-detection contract for `AccountStore`. The Phase 2
/// Plaid sync depends on `upsert` returning `true` only on actual change so
/// the NotificationCenter event doesn't fire on no-op syncs.
@Suite("AccountStore")
struct AccountStoreTests {

    private func makeStore() throws -> AccountStore {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return AccountStore(modelContainer: container)
    }

    private func sampleAccount(
        id: String = "acc-1",
        name: String = "Chase Checking",
        balance: Decimal? = Decimal(string: "1234.56")
    ) -> FinanceAccount {
        FinanceAccount(
            id: id,
            institutionId: "ins_3",
            institutionName: "Chase",
            name: name,
            officialName: "Chase Total Checking",
            mask: "0001",
            kind: .checking,
            currency: "USD",
            currentBalance: balance,
            availableBalance: Decimal(string: "1200.00"),
            limitAmount: nil,
            balanceCapturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test
    func upsertRoundTripsAllFieldsIncludingDecimalAndKind() async throws {
        let store = try makeStore()
        let dto = sampleAccount()
        let inserted = try await store.upsert(dto)
        #expect(inserted == true)

        let read = try await store.get(id: dto.id)
        let got = try #require(read)
        #expect(got.id == dto.id)
        #expect(got.institutionId == dto.institutionId)
        #expect(got.institutionName == dto.institutionName)
        #expect(got.name == dto.name)
        #expect(got.officialName == dto.officialName)
        #expect(got.mask == dto.mask)
        #expect(got.kind == .checking)
        #expect(got.currency == "USD")
        // Decimal? balances survive intact — no Double round-trip loss.
        #expect(got.currentBalance == Decimal(string: "1234.56"))
        #expect(got.availableBalance == Decimal(string: "1200.00"))
        #expect(got.limitAmount == nil)
        #expect(got.balanceCapturedAt == dto.balanceCapturedAt)
    }

    @Test
    func upsertReturnsTrueWhenFieldChanges() async throws {
        let store = try makeStore()
        _ = try await store.upsert(sampleAccount(name: "Chase Checking"))
        let renamed = sampleAccount(name: "Primary Checking")
        let changed = try await store.upsert(renamed)
        #expect(changed == true)
        let read = try await store.get(id: renamed.id)
        #expect(read?.name == "Primary Checking")
    }

    @Test
    func upsertReturnsFalseOnUnchangedRow() async throws {
        let store = try makeStore()
        let dto = sampleAccount()
        _ = try await store.upsert(dto)
        // Same DTO again — no field changes; the projection's `update`
        // returns `false`, which the store surfaces.
        let result = try await store.upsert(dto)
        #expect(result == false)
        // And we still only have one row.
        #expect(try await store.count() == 1)
    }
}
