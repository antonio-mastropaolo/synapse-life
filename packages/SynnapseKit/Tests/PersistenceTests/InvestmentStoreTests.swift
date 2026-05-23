import Foundation
import Testing
import SwiftData
@testable import Persistence
@testable import Models

/// Composite-key + value-sorted-projection contract for `InvestmentStore`.
@Suite("InvestmentStore")
struct InvestmentStoreTests {

    private func makeStore() throws -> InvestmentStore {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return InvestmentStore(modelContainer: container)
    }

    private func position(
        accountId: String,
        securityId: String,
        price: Decimal,
        quantity: Decimal,
        ticker: String
    ) -> InvestmentPosition {
        let value = price * quantity
        return InvestmentPosition(
            securityId: securityId,
            accountId: accountId,
            accountName: "Brokerage",
            ticker: ticker,
            name: ticker,
            kind: .stock,
            quantity: quantity,
            price: price,
            value: value,
            costBasis: nil,
            unrealizedPnL: nil,
            unrealizedPnLPct: nil,
            currency: "USD"
        )
    }

    @Test
    func compositeIdAndForAccountSortedByValueDesc() async throws {
        let store = try makeStore()
        let acc = "acc-broker"
        // Two positions with very different `value`s so the desc sort is
        // observable.
        let aapl = position(accountId: acc, securityId: "sec-aapl",
                            price: Decimal(200), quantity: Decimal(10),
                            ticker: "AAPL") // value 2000
        let msft = position(accountId: acc, securityId: "sec-msft",
                            price: Decimal(400), quantity: Decimal(20),
                            ticker: "MSFT") // value 8000

        #expect(try await store.upsert(aapl) == true)
        #expect(try await store.upsert(msft) == true)

        // The DTO's synthesized id formula must match what the persisted
        // row stores. The DTO computes `"\(accountId):\(securityId)"`.
        #expect(aapl.id == "\(acc):sec-aapl")
        #expect(msft.id == "\(acc):sec-msft")

        let rows = try await store.forAccount(acc)
        #expect(rows.count == 2)
        // Sorted by value desc → MSFT (8000) before AAPL (2000).
        #expect(rows[0].id == msft.id)
        #expect(rows[1].id == aapl.id)
    }

    @Test
    func reUpsertWithNewPriceUpdatesValue() async throws {
        let store = try makeStore()
        let acc = "acc-broker"
        let original = position(accountId: acc, securityId: "sec-aapl",
                                price: Decimal(100), quantity: Decimal(10),
                                ticker: "AAPL") // value 1000
        _ = try await store.upsert(original)

        let updated = position(accountId: acc, securityId: "sec-aapl",
                               price: Decimal(150), quantity: Decimal(10),
                               ticker: "AAPL") // value 1500
        let changed = try await store.upsert(updated)
        #expect(changed == true)

        let rows = try await store.forAccount(acc)
        #expect(rows.count == 1)
        #expect(rows[0].price == Decimal(150))
        #expect(rows[0].value == Decimal(1500))
    }
}
