import Foundation
import Observation
import SwiftUI
import Models

/// Snapshot the personal screen renders: a cached list of accounts plus the
/// derived net worth and allocation breakdown. All Decimal — no Double.
public struct FinancePersonalSnapshot: Sendable, Equatable {
    public let accounts: [FinanceAccount]
    public let netWorth: Decimal?
    public let allocation: [AllocationSlice]

    public init(
        accounts: [FinanceAccount],
        netWorth: Decimal?,
        allocation: [AllocationSlice]
    ) {
        self.accounts = accounts
        self.netWorth = netWorth
        self.allocation = allocation
    }
}

public enum FinancePersonalState: Sendable, Equatable {
    case idle
    case loading
    case ready(FinancePersonalSnapshot)
    case error(String)
}

@MainActor
@Observable
public final class FinancePersonalViewModel {
    public private(set) var state: FinancePersonalState = .idle
    public private(set) var concealBalances: Bool = false
    public var selectedAccount: FinanceAccount?

    /// AI insights strip below the hero. The personal pane owns the
    /// VM so the cards re-rank whenever accounts refresh. Lives in the
    /// finance VM rather than the view so snapshot tests can inject
    /// deterministic cards via `injectForSnapshots(insights:)`.
    public let insights: InsightsViewModel

    /// Latest transactions snapshot used to derive insights. Fetched as
    /// part of `refresh()`. Kept here so the command bar's `AskContext`
    /// has a single source of truth.
    public private(set) var recentTransactions: [Models.Transaction] = []

    private let api: FinanceAPI
    private let repository: FinanceRepository

    public init(api: FinanceAPI, insightsAPI: InsightsAPI = LocalStubInsightsAPI()) {
        self.api = api
        self.repository = FinanceRepository(api: api)
        self.insights = InsightsViewModel(api: insightsAPI)
    }

    public func refresh() async {
        state = .loading
        do {
            try await repository.refreshAccounts()
            let accounts = await repository.accounts
            // Also pull a recent transactions window for insights + the
            // command bar's AskContext. Best-effort: if the route is
            // empty or fails, the personal hero still paints.
            await fetchRecentTransactions()
            do {
                let netWorth = try PortfolioReducer.netWorth(accounts)
                let allocation = try PortfolioReducer.allocation(accounts)
                state = .ready(FinancePersonalSnapshot(
                    accounts: accounts, netWorth: netWorth, allocation: allocation
                ))
            } catch {
                // Mixed-currency without fx rates: still surface the accounts
                // but the net worth row will show "— mixed currencies".
                state = .ready(FinancePersonalSnapshot(
                    accounts: accounts, netWorth: nil, allocation: []
                ))
            }
            insights.refresh(accounts: accounts, transactions: recentTransactions)
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func fetchRecentTransactions() async {
        do {
            let result = try await api.transactions(accountId: nil, cursor: nil)
            recentTransactions = result.rows
        } catch {
            // Quiet: insights tolerate an empty transactions snapshot.
            recentTransactions = []
        }
    }

    /// Wire `scenePhase` from `.onChange(of: scenePhase)` in the view —
    /// when the OS reports the scene leaving `.active`, we flip the
    /// conceal-balances flag so the app-switcher snapshot doesn't leak
    /// balances onto the recents thumbnail. Locked by snapshot test.
    public func scenePhaseDidChange(_ phase: ScenePhase) {
        concealBalances = phase != .active
    }

    public func selectAccount(_ account: FinanceAccount?) {
        selectedAccount = account
    }

    /// Build a per-account transactions view model on demand. Re-uses the
    /// underlying `FinanceAPI` so the mock can observe both surfaces from
    /// one place.
    public func transactionsViewModel(for account: FinanceAccount) -> FinanceTransactionsViewModel {
        FinanceTransactionsViewModel(api: api, accountId: account.id)
    }

    /// Test seam — used by the snapshot suite to inject a deterministic
    /// state without going through `MockFinanceAPI`.
    public func injectForSnapshots(state: FinancePersonalState) {
        self.state = state
    }
}
