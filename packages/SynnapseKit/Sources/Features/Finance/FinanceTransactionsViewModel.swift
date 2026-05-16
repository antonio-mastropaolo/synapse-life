import Foundation
import Observation
import Models

public enum FinanceTransactionsState: Sendable, Equatable {
    case idle
    case loading
    case results([Transaction])
    case empty
    case error(String)
}

@MainActor
@Observable
public final class FinanceTransactionsViewModel {
    public private(set) var state: FinanceTransactionsState = .idle
    public private(set) var rows: [Transaction] = []
    public let accountId: String?
    public var filter: LedgerFilter = LedgerFilter()

    private let api: FinanceAPI
    private let repository: FinanceRepository

    public init(api: FinanceAPI, accountId: String? = nil) {
        self.api = api
        self.accountId = accountId
        self.repository = FinanceRepository(api: api)
    }

    public func refresh() async {
        state = .loading
        do {
            try await repository.refreshTransactions(accountId: accountId)
            self.rows = await repository.transactions
            let visible = filter.apply(to: rows)
            state = visible.isEmpty ? .empty : .results(visible)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func loadMore() async {
        do {
            try await repository.loadMoreTransactions()
            self.rows = await repository.transactions
            let visible = filter.apply(to: rows)
            state = visible.isEmpty ? .empty : .results(visible)
        } catch {
            // Loading more is non-fatal; keep the existing results.
        }
    }

    public func filtered() -> [Transaction] {
        filter.apply(to: rows)
    }

    public func injectForSnapshots(transactions: [Transaction], filter: LedgerFilter) {
        self.rows = transactions
        self.filter = filter
        let visible = filter.apply(to: transactions)
        self.state = visible.isEmpty ? .empty : .results(visible)
    }
}
