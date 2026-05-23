import Foundation
import Testing
@testable import Persistence
@testable import Models

/// The most important test in this target. The whole point of using
/// `Decimal` over `Double` for money is exactness; if SwiftData secretly
/// promotes through Double on the way to the SQLite file, all the careful
/// projection work is for nothing. This test pins the contract.
///
/// If any fixture fails, the recommended fix is to persist as a
/// canonicalized String (`"\(decimal)"`) on the `@Model` and parse back via
/// `Decimal(string:)` at read time. That change belongs in
/// `Sources/Persistence/Models/PersistedTransaction.swift`, NOT here.
@Suite("DecimalRoundTrip")
struct DecimalRoundTripTests {

    /// 20 fixtures: the spec-required ones (very small, very large, zero,
    /// negative micro, classic float gotchas) plus padding so we don't miss
    /// a width-dependent rounding path.
    static let fixtures: [String] = [
        "-12345.67",
        "0.01",
        "999999999999.99",
        "0",
        "-0.001",
        "0.30000000000000004",   // 0.1 + 0.2 in Double
        "0.3333",                // 1.0/3.0 truncated to 4 decimals
        "1.00",                  // trailing-zero canonicalization risk
        "-0.00",                 // negative zero edge case
        "0.1",
        "0.2",
        "1000000.00",
        "-1000000.00",
        "0.123456789",
        "-0.123456789",
        "42",
        "-42",
        "100000000.55",
        "-100000000.55",
        "0.00001"
    ]

    private func makeStore() throws -> TransactionStore {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return TransactionStore(modelContainer: container)
    }

    private func makeTransaction(id: String, amountString: String) throws -> Transaction {
        let amount = try #require(
            Decimal(string: amountString),
            "Decimal(string: \"\(amountString)\") should not be nil — fixture bug"
        )
        return Transaction(
            id: id,
            accountId: "acc-1",
            accountName: "Checking",
            amount: amount,
            currency: "USD",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Fixture \(id)",
            merchantName: nil,
            category: .unknown,
            subcategory: nil,
            pending: false
        )
    }

    @Test
    func singleHeadlineFixturePreservesExactness() async throws {
        // The headline assertion the spec requires verbatim.
        let store = try makeStore()
        let expected = Decimal(string: "-12345.67")
        let dto = try makeTransaction(id: "headline", amountString: "-12345.67")
        _ = try await store.upsert(dto)

        let read = try await store.get(id: "headline")
        let got = try #require(read)
        #expect(got.amount == expected)
    }

    @Test
    func allFixturesRoundTripExactly() async throws {
        let store = try makeStore()

        // Write everything first so a single failure doesn't mask the others.
        for (i, s) in Self.fixtures.enumerated() {
            let dto = try makeTransaction(id: "fx-\(i)", amountString: s)
            _ = try await store.upsert(dto)
        }

        // Then read back and assert each one against its canonical Decimal.
        for (i, s) in Self.fixtures.enumerated() {
            let expected = try #require(Decimal(string: s))
            let read = try #require(try await store.get(id: "fx-\(i)"))
            let actual = try #require(
                read.amount,
                "fx-\(i) (\"\(s)\") came back with amount == nil — the persistence layer dropped the value"
            )
            // The comment in the report should make the diagnosis quick:
            // if THIS line fires, SwiftData promoted to Double somewhere
            // and we need to switch to String-of-Decimal storage in
            // PersistedTransaction.
            #expect(
                actual == expected,
                "fx-\(i): expected \(expected) for \"\(s)\", got \(actual). SwiftData did not preserve Decimal exactness."
            )
        }
    }
}
