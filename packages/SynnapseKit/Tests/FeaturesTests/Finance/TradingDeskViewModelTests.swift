import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func position(ticker: String, value: Double, price: Double = 100) -> InvestmentPosition {
    InvestmentPosition(
        securityId: "sec_\(ticker)",
        accountId: "acc_brk",
        accountName: "Brokerage",
        ticker: ticker,
        name: "\(ticker) Corp",
        kind: .stock,
        quantity: Decimal(string: String(value / price)) ?? Decimal(value / price),
        price: Decimal(string: String(price)) ?? Decimal(price),
        value: Decimal(string: String(value)) ?? Decimal(value),
        costBasis: nil,
        unrealizedPnL: nil,
        unrealizedPnLPct: nil,
        currency: "USD"
    )
}

@MainActor
@Suite("TradingDeskViewModel")
struct TradingDeskViewModelTests {

    @Test func startsIdleAndPopulatesPositions() async {
        let api = MockFinanceAPI()
        await api.setInvestments([
            position(ticker: "AAPL", value: 50_000),
            position(ticker: "MSFT", value: 30_000)
        ])
        let vm = TradingDeskViewModel(api: api)
        if case .idle = vm.state {} else {
            Issue.record("expected idle initial state")
        }
        await vm.refresh()
        if case .ready = vm.state {} else {
            Issue.record("expected ready, got \(vm.state)")
        }
        #expect(vm.positions.count == 2)
        // Largest position auto-selected.
        #expect(vm.selectedSymbol == "AAPL")
    }

    @Test func emptyPortfolioSurfacesEmptyState() async {
        let api = MockFinanceAPI()
        await api.setInvestments([])
        let vm = TradingDeskViewModel(api: api)
        await vm.refresh()
        if case .empty = vm.state {} else {
            Issue.record("expected empty, got \(vm.state)")
        }
        #expect(vm.selectedSymbol == nil)
    }

    @Test func stickyTickerSurvivesRefreshWhenStillPresent() async {
        let api = MockFinanceAPI()
        await api.setInvestments([
            position(ticker: "AAPL", value: 50_000),
            position(ticker: "MSFT", value: 30_000)
        ])
        let vm = TradingDeskViewModel(api: api)
        await vm.refresh()
        vm.select(symbol: "MSFT")
        #expect(vm.selectedSymbol == "MSFT")
        // Refresh — MSFT still in the list, selection must persist.
        await vm.refresh()
        #expect(vm.selectedSymbol == "MSFT")
    }

    @Test func stickyTickerFallsBackWhenSelectionDisappears() async {
        let api = MockFinanceAPI()
        await api.setInvestments([
            position(ticker: "AAPL", value: 50_000),
            position(ticker: "MSFT", value: 30_000)
        ])
        let vm = TradingDeskViewModel(api: api)
        await vm.refresh()
        vm.select(symbol: "MSFT")
        // Refresh into a portfolio that no longer holds MSFT.
        await api.setInvestments([position(ticker: "NVDA", value: 80_000)])
        await vm.refresh()
        // Selection re-anchors to the new top-by-value.
        #expect(vm.selectedSymbol == "NVDA")
    }

    @Test func selectIgnoresUnknownSymbol() async {
        let api = MockFinanceAPI()
        await api.setInvestments([position(ticker: "AAPL", value: 1_000)])
        let vm = TradingDeskViewModel(api: api)
        await vm.refresh()
        vm.select(symbol: "DOESNT_EXIST")
        // Selection unchanged.
        #expect(vm.selectedSymbol == "AAPL")
    }

    @Test func watchlistDeduplicatesByTickerAcrossAccounts() async {
        let api = MockFinanceAPI()
        await api.setInvestments([
            position(ticker: "AAPL", value: 10_000),
            // Same ticker, different account, bigger position. Watchlist
            // should pick this one.
            InvestmentPosition(
                securityId: "sec_AAPL",
                accountId: "acc_ira",
                accountName: "IRA",
                ticker: "AAPL", name: "Apple",
                kind: .stock,
                quantity: Decimal(100), price: Decimal(200),
                value: Decimal(20_000),
                costBasis: nil, unrealizedPnL: nil, unrealizedPnLPct: nil,
                currency: "USD"
            )
        ])
        let vm = TradingDeskViewModel(api: api)
        await vm.refresh()
        let watch = vm.watchlist
        #expect(watch.count == 1)
        #expect(watch.first?.value == Decimal(20_000))
    }

    @Test func intradayPointsAreNonEmptyAndDeterministic() {
        let pos = position(ticker: "AAPL", value: 50_000, price: 100)
        let api = MockFinanceAPI()
        let vm = TradingDeskViewModel(api: api)
        let a = vm.intradayPoints(for: pos)
        let b = vm.intradayPoints(for: pos)
        #expect(a.count == 78)
        #expect(a == b) // deterministic walk
    }

    @Test func paneVisibilityIsConfigurable() async {
        let api = MockFinanceAPI()
        await api.setInvestments([position(ticker: "AAPL", value: 1_000)])
        let vm = TradingDeskViewModel(api: api)
        await vm.refresh()
        vm.panes = .init(watchlist: true, chart: true, positions: false, orders: false)
        #expect(vm.panes.watchlist == true)
        #expect(vm.panes.positions == false)
    }

    @Test func errorStateIsExposedOnAPIFailure() async {
        let api = MockFinanceAPI()
        await api.setNextError(APIError.server(status: 500))
        let vm = TradingDeskViewModel(api: api)
        await vm.refresh()
        if case .error = vm.state {} else {
            Issue.record("expected error, got \(vm.state)")
        }
    }
}
