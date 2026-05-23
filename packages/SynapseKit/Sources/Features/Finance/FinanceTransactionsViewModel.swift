import Foundation
import Observation
import Models

/// State of the Transactions surface. The ready payload is already grouped
/// by card so the view's only job is to render the sections — all filtering
/// and bucketing happens in [[LedgerFilter]].
public enum FinanceTransactionsState: Sendable, Equatable {
    case idle
    case loading
    case ready([CardGroup])
    case error(String)
}

@MainActor
@Observable
public final class FinanceTransactionsViewModel {
    public private(set) var state: FinanceTransactionsState = .idle
    public private(set) var rows: [Transaction] = []
    public private(set) var accounts: [FinanceAccount] = []
    public let accountId: String?

    // Filter state. Each setter re-projects the grouped output. Categories
    // is stored as a set internally but the view drives it as radio-select
    // through `selectedCategory`.
    public var filter: LedgerFilter = LedgerFilter() {
        didSet { reproject() }
    }

    /// Convenience for the UI's single-select category chips. Nil = "All".
    public var selectedCategory: String? {
        get { filter.categories.first }
        set {
            if let value = newValue {
                filter.categories = [value]
            } else {
                filter.categories = []
            }
        }
    }

    public var searchText: String {
        get { filter.searchText }
        set { filter.searchText = newValue }
    }

    public var showPending: Bool {
        get { filter.showPending }
        set { filter.showPending = newValue }
    }

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
            // Fan out: accounts (for section headers) and transactions
            // (for rows) in parallel. Either failing is fatal to the
            // surface — we can't render grouped sections without both.
            async let accountsTask: Void = repository.refreshAccounts()
            async let transactionsTask: Void = repository.refreshTransactions(
                accountId: accountId
            )
            try await accountsTask
            try await transactionsTask
            self.accounts = await repository.accounts
            self.rows = await repository.transactions
            reproject()
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func loadMore() async {
        do {
            try await repository.loadMoreTransactions()
            self.rows = await repository.transactions
            reproject()
        } catch {
            // Loading more is non-fatal; keep the existing results.
        }
    }

    /// All known category strings across the current row set, sorted for a
    /// stable chip order. Used by the view to render the chip rail.
    public var availableCategories: [String] {
        var seen = Set<String>()
        for row in rows {
            if case .knownCategory(let s) = row.category, !s.isEmpty {
                seen.insert(s)
            }
        }
        return seen.sorted()
    }

    /// Recompute the grouped output from the current filter + row set.
    /// Pure projection — never touches the network.
    public func reproject() {
        let groups = filter.groupByCard(rows: rows, accounts: accounts)
        state = .ready(groups)
    }

    /// Test/preview hook. Injects rows + accounts + filter, then projects.
    public func injectForSnapshots(
        transactions: [Transaction],
        accounts: [FinanceAccount],
        filter: LedgerFilter
    ) {
        self.rows = transactions
        self.accounts = accounts
        self.filter = filter
        reproject()
    }
}
