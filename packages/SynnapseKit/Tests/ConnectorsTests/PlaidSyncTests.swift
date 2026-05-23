import Foundation
import Testing
import SwiftData
@testable import Connectors
@testable import Models
@testable import Persistence

/// End-to-end seam test: stub connector → real (ephemeral) stores → result
/// surface. The point is to prove the wiring, not the connector — the
/// connector is locked separately in `StubPlaidConnectorTests`.
@Suite("PlaidSync")
struct PlaidSyncTests {

    private func makeStores() throws -> (
        AccountStore, TransactionStore, InvestmentStore, AuditLogStore
    ) {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        return (
            AccountStore(modelContainer: container),
            TransactionStore(modelContainer: container),
            InvestmentStore(modelContainer: container),
            AuditLogStore(modelContainer: container)
        )
    }

    @Test
    func syncWritesAccountsTransactionsAndInvestmentsAndAudits() async throws {
        let (accounts, txns, investments, audit) = try makeStores()
        let stub = StubPlaidConnector()
        let sync = PlaidSync(
            connector: stub,
            accountStore: accounts,
            transactionStore: txns,
            investmentStore: investments,
            auditLog: audit
        )

        let result = try await sync.sync(itemId: "item-stub-1", cursor: nil)

        // 1. Accounts written.
        let acctCount = try await accounts.count()
        #expect(acctCount == 2)

        // 2. Transactions written with the correct count.
        let txnCount = try await txns.count()
        #expect(txnCount == 3)
        #expect(result.addedCount == 3)
        #expect(result.modifiedCount == 0)
        #expect(result.removedCount == 0)

        // 3. Investments written.
        let invCount = try await investments.count()
        #expect(invCount == 2)

        // 4. Audit row recorded with outcome == .ok.
        let recent = try await audit.recent(limit: 10)
        #expect(recent.count == 1)
        let row = try #require(recent.first)
        #expect(row.kind == .transactionSync)
        #expect(row.subject == "plaid:item-stub-1")
        #expect(row.outcome == .ok)

        // 5. Cursor returned matches the stub's first-call cursor.
        // The stub advances cursorCounter once per call; after one sync
        // the result cursor must be non-empty and distinct from `nil`.
        #expect(!result.cursor.isEmpty)
    }

    @Test
    func syncCursorMatchesConnectorNextCursor() async throws {
        let (accounts, txns, investments, audit) = try makeStores()
        let stub = StubPlaidConnector()

        // Pull the stub's first-call cursor directly so we can compare
        // against what PlaidSync surfaces. We use a *separate* stub
        // instance below for the actual sync so the counter starts
        // identically.
        let expectedDelta = try await stub.syncTransactions(
            itemId: "item-stub-1",
            cursor: nil
        )
        let expectedCursor = expectedDelta.nextCursor

        let stub2 = StubPlaidConnector()
        let sync = PlaidSync(
            connector: stub2,
            accountStore: accounts,
            transactionStore: txns,
            investmentStore: investments,
            auditLog: audit
        )
        let result = try await sync.sync(itemId: "item-stub-1", cursor: nil)
        #expect(result.cursor == expectedCursor)
    }

    @Test
    func syncWritesErrorAuditWhenConnectorThrows() async throws {
        let (accounts, txns, investments, audit) = try makeStores()
        let failing = FailingPlaidConnector()
        let sync = PlaidSync(
            connector: failing,
            accountStore: accounts,
            transactionStore: txns,
            investmentStore: investments,
            auditLog: audit
        )

        await #expect(throws: PlaidConnectorError.self) {
            _ = try await sync.sync(itemId: "item-fail", cursor: nil)
        }

        let rows = try await audit.recent(limit: 10)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.kind == .transactionSync)
        #expect(row.outcome == .error)
    }
}

/// Always-throwing connector for the negative-path audit test.
private actor FailingPlaidConnector: PlaidConnector {
    func createLinkToken(userId: String) async throws -> PlaidLinkToken {
        throw PlaidConnectorError.notImplemented
    }
    func exchangePublicToken(_ publicToken: String) async throws -> PlaidItem {
        throw PlaidConnectorError.notImplemented
    }
    func syncTransactions(
        itemId: String,
        cursor: String?
    ) async throws -> PlaidSyncDelta {
        throw PlaidConnectorError.notImplemented
    }
    func fetchAccounts(itemId: String) async throws -> [FinanceAccount] {
        throw PlaidConnectorError.notImplemented
    }
    func fetchInvestments(itemId: String) async throws -> [InvestmentPosition] {
        throw PlaidConnectorError.notImplemented
    }
    func removeItem(itemId: String) async throws {
        throw PlaidConnectorError.notImplemented
    }
}
