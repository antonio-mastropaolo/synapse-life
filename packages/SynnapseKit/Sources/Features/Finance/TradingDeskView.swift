import SwiftUI
import Models
import DesignSystem
import SynnapseCharts

/// Multi-pane Trading Desk surface. Layout:
///
/// ```
/// ┌───────────────┬───────────────────────────────┐
/// │  Watchlist    │       Ticker chart            │
/// │  (left col)   │       (right top)             │
/// │               ├───────────────────────────────┤
/// │               │  Positions    │   Orders      │
/// │               │  (right       │   (right      │
/// │               │   bottom-     │   bottom-     │
/// │               │   left)       │   right)      │
/// └───────────────┴───────────────────────────────┘
/// ```
///
/// macOS only in M8. Uses `HSplitView` + `VSplitView` for native resize
/// affordances. iOS gets the placeholder view below.
@MainActor
public struct TradingDeskView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: TradingDeskViewModel

    public init(viewModel: TradingDeskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .task {
                if case .idle = viewModel.state { await viewModel.refresh() }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macLayout
        #else
        TradingDeskPlaceholderView()
        #endif
    }

    #if os(macOS)
    private var macLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return HSplitView {
            watchlistPane
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            VSplitView {
                chartPane
                    .frame(minHeight: 200, idealHeight: 320)
                HSplitView {
                    positionsPane
                        .frame(minWidth: 280, idealWidth: 420)
                    ordersPane
                        .frame(minWidth: 220, idealWidth: 320)
                }
                .frame(minHeight: 160, idealHeight: 220)
            }
            .frame(minWidth: 540)
        }
        .background(tokens.background.color)
        .navigationTitle("Trading Desk")
    }

    // MARK: - Watchlist pane

    private var watchlistPane: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 0) {
            paneHeader("Watchlist")
            switch viewModel.state {
            case .idle, .loading:
                Spacer()
                HStack { Spacer(); ProgressView().tint(tokens.foregroundSecondary.color); Spacer() }
                Spacer()
            case .empty:
                Spacer()
                Text("No positions")
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .frame(maxWidth: .infinity)
                Spacer()
            case .error(let msg):
                Text(msg)
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.lossAccent.color)
                    .padding()
            case .ready:
                List(selection: Binding<String?>(
                    get: { viewModel.selectedSymbol },
                    set: { viewModel.select(symbol: $0) }
                )) {
                    ForEach(viewModel.watchlist) { pos in
                        WatchlistRow(position: pos)
                            .tag(pos.ticker ?? "")
                            .listRowBackground(tokens.surface.color)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(tokens.surface.color)
            }
        }
        .background(tokens.surface.color)
    }

    // MARK: - Chart pane

    private var chartPane: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 0) {
            chartHeader
            ZStack {
                tokens.background.color
                if let position = viewModel.selectedPosition {
                    let points = viewModel.intradayPoints(for: position)
                    MoneyLineChart(
                        points: points,
                        currency: position.currency,
                        accent: tokens.gainAccent.color
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    Text("Select a ticker to chart")
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
        }
        .background(tokens.background.color)
    }

    @ViewBuilder
    private var chartHeader: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let position = viewModel.selectedPosition {
                Text(position.ticker ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(position.name ?? "")
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(position.price.formatted(.currency(code: position.currency)))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    if let pnl = position.unrealizedPnLPct {
                        let n = NSDecimalNumber(decimal: pnl).doubleValue
                        Text(String(format: "%+.2f%%", n))
                            .font(tokens.tickerFont(size: 10, weight: .semibold))
                            .foregroundStyle(n >= 0 ? tokens.gainAccent.color : tokens.lossAccent.color)
                    }
                }
            } else {
                Text("Trading Desk")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tokens.surface.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.15))
                .frame(height: 1)
        }
    }

    // MARK: - Positions pane

    private var positionsPane: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 0) {
            paneHeader("Positions")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.positions) { pos in
                        PositionRow(position: pos)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                pos.ticker == viewModel.selectedSymbol
                                    ? tokens.accent.color.opacity(0.10)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.select(symbol: pos.ticker)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(tokens.surface.color)
    }

    // MARK: - Orders pane (read-only)

    private var ordersPane: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 0) {
            paneHeader("Orders")
            VStack(spacing: 6) {
                Text("No open orders")
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("Trading Desk is read-only.")
                    .font(tokens.tickerFont(size: 9))
                    .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(tokens.surface.color)
    }

    private func paneHeader(_ title: String) -> some View {
        let tokens = theme.tokens(for: scheme)
        return Text(title)
            .font(tokens.tickerFont(size: 10, weight: .semibold))
            .foregroundStyle(tokens.foregroundSecondary.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.surface.color)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tokens.foregroundSecondary.color.opacity(0.15))
                    .frame(height: 1)
            }
    }
    #endif
}

// MARK: - Watchlist row

struct WatchlistRow: View {
    let position: InvestmentPosition
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(position.ticker ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(position.name ?? "")
                    .font(tokens.tickerFont(size: 9))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(position.price.formatted(.currency(code: position.currency)))
                    .font(tokens.tickerFont(size: 11, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                if let pct = position.unrealizedPnLPct {
                    let n = NSDecimalNumber(decimal: pct).doubleValue
                    Text(String(format: "%+.1f%%", n))
                        .font(tokens.tickerFont(size: 9))
                        .foregroundStyle(n >= 0 ? tokens.gainAccent.color : tokens.lossAccent.color)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Positions row

struct PositionRow: View {
    let position: InvestmentPosition
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 12) {
            Text(position.ticker ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .frame(width: 60, alignment: .leading)
            Text(position.accountName)
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(1)
            Spacer()
            Text("Qty \(formatQty(position.quantity))")
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(position.value.formatted(.currency(code: position.currency)))
                .font(tokens.tickerFont(size: 11, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .frame(minWidth: 80, alignment: .trailing)
        }
    }

    private func formatQty(_ q: Decimal) -> String {
        let n = NSDecimalNumber(decimal: q).doubleValue
        return String(format: "%.2f", n)
    }
}

// MARK: - iOS placeholder

@MainActor
public struct TradingDeskPlaceholderView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ZStack {
            tokens.background.color.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "rectangle.split.3x3")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("Trading Desk")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Open on Mac or iPad")
                    .font(.system(size: 14))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("A desktop-class multi-pane layout. Coming to iPad once Stage Manager support lands; iPhone keeps the personal hub view.")
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .accessibilityIdentifier("trading.desk.placeholder")
    }
}
