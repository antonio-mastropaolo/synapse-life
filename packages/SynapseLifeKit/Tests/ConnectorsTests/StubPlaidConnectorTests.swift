import Foundation
import Testing
@testable import Connectors
@testable import Models

/// Locks the stub's deterministic fixture shape. Any change to the stub's
/// outputs must update these assertions — that's the point of the lock.
@Suite("StubPlaidConnector")
struct StubPlaidConnectorTests {

    @Test
    func createLinkTokenReturnsTokenExpiringInFourHours() async throws {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let stub = StubPlaidConnector(now: now)
        let token = try await stub.createLinkToken(userId: "user-1")
        #expect(token.token.contains("user-1"))
        #expect(token.expiration == now.addingTimeInterval(4 * 3600))
    }

    @Test
    func exchangePublicTokenReturnsKeychainRefNotRawToken() async throws {
        let stub = StubPlaidConnector()
        let item = try await stub.exchangePublicToken("public-sandbox-xxx")
        #expect(item.id == "item-stub-1")
        #expect(item.institutionId == "ins_109508")
        #expect(item.institutionName == "First Platypus Bank")
        // The keychain alias must NOT contain the raw public token.
        #expect(item.accessTokenRef.hasPrefix("kc:"))
        #expect(!item.accessTokenRef.contains("public-sandbox"))
    }

    @Test
    func syncTransactionsReturnsThreeAddedOnFirstCallEmptyOnSecond() async throws {
        let stub = StubPlaidConnector()
        let first = try await stub.syncTransactions(itemId: "item-stub-1", cursor: nil)
        #expect(first.added.count == 3)
        #expect(first.modified.isEmpty)
        #expect(first.removedIds.isEmpty)
        #expect(first.hasMore == false)
        // The cursor must advance — second call must not see the same value.
        let firstCursor = first.nextCursor
        #expect(!firstCursor.isEmpty)

        let second = try await stub.syncTransactions(
            itemId: "item-stub-1",
            cursor: firstCursor
        )
        #expect(second.added.isEmpty)
        #expect(second.modified.isEmpty)
        #expect(second.removedIds.isEmpty)
        #expect(second.nextCursor != firstCursor)
        #expect(second.hasMore == false)
    }

    @Test
    func fetchAccountsReturnsOneCheckingOneCredit() async throws {
        let stub = StubPlaidConnector()
        let accounts = try await stub.fetchAccounts(itemId: "item-stub-1")
        #expect(accounts.count == 2)
        #expect(accounts.contains { $0.kind == .checking })
        #expect(accounts.contains { $0.kind == .credit })
        // Liability classification flows from the kind.
        let credit = try #require(accounts.first { $0.kind == .credit })
        #expect(credit.kind.isLiability == true)
        #expect(credit.limitAmount == Decimal(string: "2000.00"))
    }

    @Test
    func fetchInvestmentsReturnsAaplAndVoo() async throws {
        let stub = StubPlaidConnector()
        let positions = try await stub.fetchInvestments(itemId: "item-stub-1")
        #expect(positions.count == 2)
        let tickers = Set(positions.compactMap { $0.ticker })
        #expect(tickers == ["AAPL", "VOO"])
        let aapl = try #require(positions.first { $0.ticker == "AAPL" })
        #expect(aapl.kind == .stock)
        #expect(aapl.value == Decimal(string: "1950.00"))
        let voo = try #require(positions.first { $0.ticker == "VOO" })
        #expect(voo.kind == .etf)
    }

    @Test
    func removeItemDoesNotThrow() async throws {
        let stub = StubPlaidConnector()
        try await stub.removeItem(itemId: "item-stub-1")
    }
}
