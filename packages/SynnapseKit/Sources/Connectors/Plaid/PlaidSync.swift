import Foundation
import Models
import Persistence

/// One-shot sync coordinator: pulls accounts, paginates the transactions
/// delta until exhausted, pulls investments, and writes everything through
/// the actor-backed stores. Emits one `AuditLogStore` row per sync attempt.
///
/// This actor is the *only* place that knows about the order of writes —
/// stores stay agnostic, and the connector stays agnostic. Phase 4's
/// background-refresh task will call `sync(itemId:cursor:)` from a
/// BGAppRefreshTask handler.
public actor PlaidSync {

    private let connector: PlaidConnector
    private let accountStore: AccountStore
    private let transactionStore: TransactionStore
    private let investmentStore: InvestmentStore
    private let auditLog: AuditLogStore

    public init(
        connector: PlaidConnector,
        accountStore: AccountStore,
        transactionStore: TransactionStore,
        investmentStore: InvestmentStore,
        auditLog: AuditLogStore
    ) {
        self.connector = connector
        self.accountStore = accountStore
        self.transactionStore = transactionStore
        self.investmentStore = investmentStore
        self.auditLog = auditLog
    }

    /// Run the full sync pipeline. On success: one `transactionSync` audit
    /// row with `outcome == .ok` and a populated `PlaidSyncResult`. On
    /// failure: one row with `outcome == .error` and the same error is
    /// rethrown to the caller.
    public func sync(itemId: String, cursor: String?) async throws -> PlaidSyncResult {
        let subject = "plaid:\(itemId)"
        do {
            // 1. Accounts snapshot — write first so any subsequent
            //    transaction insert can reference the foreign key.
            let accounts = try await connector.fetchAccounts(itemId: itemId)
            try await accountStore.upsertAll(accounts)

            // 2. Cursor-paginated transactions. Loop until `hasMore`
            //    flips false, accumulating counts across pages.
            var currentCursor = cursor
            var addedCount = 0
            var modifiedCount = 0
            var removedCount = 0
            var lastCursor = currentCursor ?? ""

            repeat {
                let delta = try await connector.syncTransactions(
                    itemId: itemId,
                    cursor: currentCursor
                )
                let upsertBatch = delta.added + delta.modified
                if !upsertBatch.isEmpty {
                    try await transactionStore.upsertAll(upsertBatch)
                }
                if !delta.removedIds.isEmpty {
                    try await transactionStore.delete(ids: delta.removedIds)
                }
                addedCount += delta.added.count
                modifiedCount += delta.modified.count
                removedCount += delta.removedIds.count
                lastCursor = delta.nextCursor
                currentCursor = delta.nextCursor
                if !delta.hasMore { break }
            } while true

            // 3. Investments snapshot.
            let positions = try await connector.fetchInvestments(itemId: itemId)
            try await investmentStore.upsertAll(positions)

            // 4. Success audit row.
            try await auditLog.append(
                kind: .transactionSync,
                subject: subject,
                outcome: .ok
            )

            return PlaidSyncResult(
                addedCount: addedCount,
                modifiedCount: modifiedCount,
                removedCount: removedCount,
                cursor: lastCursor
            )
        } catch {
            // Best-effort: failure to write the audit row must not
            // mask the original error.
            try? await auditLog.append(
                kind: .transactionSync,
                subject: subject,
                detail: String(describing: error),
                outcome: .error
            )
            throw error
        }
    }
}
