import Foundation
import Models

/// Caches the finance surface state: account list (with ETag), transaction
/// page cache (with cursor), and the latest investments snapshot.
/// Concurrency-safe via the actor; view models read snapshots on the main
/// actor.
public actor FinanceRepository {
    private let api: FinanceAPI
    private(set) public var accounts: [FinanceAccount] = []
    private(set) public var transactions: [Transaction] = []
    private(set) public var investments: [InvestmentPosition] = []
    private var accountsEtag: String?
    private var transactionsCursor: String?
    private var transactionsAccountId: String?
    private var reachedTransactionsEnd: Bool = false

    public init(api: FinanceAPI) {
        self.api = api
    }

    public func refreshAccounts() async throws {
        let response = try await api.accounts(ifNoneMatch: accountsEtag)
        if response.notModified {
            if let etag = response.etag { accountsEtag = etag }
            return
        }
        if let accounts = response.accounts {
            self.accounts = accounts
        }
        if let etag = response.etag { accountsEtag = etag }
    }

    /// Refresh the ledger. `accountId == nil` is the aggregate route;
    /// passing an accountId scopes to that account.
    public func refreshTransactions(accountId: String? = nil) async throws {
        transactionsAccountId = accountId
        let response = try await api.transactions(accountId: accountId, cursor: nil)
        transactions = response.rows
        transactionsCursor = response.nextCursor
        reachedTransactionsEnd = response.nextCursor == nil
    }

    public func loadMoreTransactions() async throws {
        if reachedTransactionsEnd { return }
        guard let cursor = transactionsCursor else {
            reachedTransactionsEnd = true
            return
        }
        let response = try await api.transactions(
            accountId: transactionsAccountId, cursor: cursor
        )
        transactions.append(contentsOf: response.rows)
        transactionsCursor = response.nextCursor
        reachedTransactionsEnd = response.nextCursor == nil
    }

    public func refreshInvestments() async throws {
        investments = try await api.investments()
    }

    public func clear() {
        accounts = []
        transactions = []
        investments = []
        accountsEtag = nil
        transactionsCursor = nil
        transactionsAccountId = nil
        reachedTransactionsEnd = false
    }
}
