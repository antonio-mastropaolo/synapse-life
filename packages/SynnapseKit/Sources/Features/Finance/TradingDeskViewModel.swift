import Foundation
import Observation
import Models
import SynnapseCharts

/// Drives the macOS-only Trading Desk surface. Reads from the same M5
/// `FinanceRepository` that backs Investments + Personal — the desk is a
/// **different presentation** of the same data, not a new ingest path.
///
/// Layout state:
///   - `selectedSymbol` is the ticker pinned in the chart pane. Sticky:
///     survives `refresh()` calls as long as the ticker still resolves in
///     the new positions list.
///   - `panes` controls which optional panes are visible. Defaults to all
///     four (watchlist, chart, positions, orders) on macOS.
///
/// Trading Desk does NOT issue orders. The "orders" pane displays orders
/// the server already has (none, today) — we never POST. Per M8 brief:
/// read-only.
@MainActor
@Observable
public final class TradingDeskViewModel {

    public enum State: Sendable, Equatable {
        case idle
        case loading
        case ready
        case empty
        case error(String)
    }

    public struct PaneVisibility: Sendable, Equatable {
        public var watchlist: Bool
        public var chart: Bool
        public var positions: Bool
        public var orders: Bool

        public init(
            watchlist: Bool = true,
            chart: Bool = true,
            positions: Bool = true,
            orders: Bool = true
        ) {
            self.watchlist = watchlist
            self.chart = chart
            self.positions = positions
            self.orders = orders
        }

        public static let allVisible = PaneVisibility()
    }

    public private(set) var state: State = .idle
    public private(set) var positions: [InvestmentPosition] = []
    public var panes: PaneVisibility = .allVisible
    public private(set) var selectedSymbol: String?

    private let api: FinanceAPI
    private let repository: FinanceRepository

    public init(api: FinanceAPI) {
        self.api = api
        self.repository = FinanceRepository(api: api)
    }

    public func refresh() async {
        state = .loading
        do {
            try await repository.refreshInvestments()
            self.positions = await repository.investments
            state = positions.isEmpty ? .empty : .ready
            // Sticky-ticker logic: keep the user's selection if it's still
            // there; otherwise drop to the largest position by value.
            if let current = selectedSymbol,
               positions.contains(where: { $0.ticker == current }) {
                // keep
            } else {
                selectedSymbol = topByValue()?.ticker
            }
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func select(symbol: String?) {
        if symbol == nil {
            selectedSymbol = nil
            return
        }
        if let symbol, positions.contains(where: { $0.ticker == symbol }) {
            selectedSymbol = symbol
        }
    }

    public var watchlist: [InvestmentPosition] {
        // Unique by ticker (a security may show up in multiple accounts);
        // largest position per ticker wins.
        var bestByTicker: [String: InvestmentPosition] = [:]
        for p in positions {
            guard let tick = p.ticker, !tick.isEmpty else { continue }
            if let existing = bestByTicker[tick] {
                if p.value > existing.value { bestByTicker[tick] = p }
            } else {
                bestByTicker[tick] = p
            }
        }
        return bestByTicker.values.sorted { $0.value > $1.value }
    }

    public var selectedPosition: InvestmentPosition? {
        guard let selectedSymbol else { return nil }
        return positions.first(where: { $0.ticker == selectedSymbol })
    }

    /// Synthetic intraday line chart. The synapse-v2 server does not yet
    /// expose `/api/finance/quote-history` — the desk renders a sparkline
    /// from a deterministic walk anchored at the position's last price,
    /// so the chart pane is never empty while the contract is in flight.
    /// Once the route lands this method swaps for a real fetch.
    public func intradayPoints(for position: InvestmentPosition) -> [MoneyTimePoint] {
        let anchor = position.price
        let asDouble = NSDecimalNumber(decimal: anchor).doubleValue
        guard asDouble > 0 else { return [] }
        // 78 5-minute bars in a US trading session — close enough for a
        // sparkline. Walk seeded by ticker so the same symbol always
        // renders the same shape.
        let bars = 78
        let seed = position.ticker?.unicodeScalars.reduce(0) { $0 + Int($1.value) } ?? 7
        let base = Date(timeIntervalSinceReferenceDate: 0)
        return (0..<bars).map { i in
            let phase = Double((seed + i) % 13) * 0.21
            let drift = sin(phase) * 0.012 * asDouble
            let level = asDouble + drift * (Double(i) / Double(bars))
            let date = base.addingTimeInterval(TimeInterval(i) * 300)
            return MoneyTimePoint(
                date: date,
                amount: Decimal(string: String(format: "%.4f", level)) ?? anchor
            )
        }
    }

    private func topByValue() -> InvestmentPosition? {
        positions
            .filter { $0.ticker?.isEmpty == false }
            .max(by: { $0.value < $1.value })
    }

    /// Test seam — drop a deterministic state in without going through
    /// the repository.
    public func injectForSnapshots(
        positions: [InvestmentPosition],
        selectedSymbol: String? = nil,
        panes: PaneVisibility = .allVisible
    ) {
        self.positions = positions
        self.panes = panes
        self.state = positions.isEmpty ? .empty : .ready
        if let selectedSymbol {
            self.selectedSymbol = selectedSymbol
        } else {
            self.selectedSymbol = topByValue()?.ticker
        }
    }
}
