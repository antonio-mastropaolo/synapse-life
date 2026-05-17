import SwiftUI
import Models
import DesignSystem
import SynnapseCharts

@MainActor
public struct FinanceInvestmentsView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: FinanceInvestmentsViewModel

    public init(viewModel: FinanceInvestmentsViewModel) {
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
        macContent
        #else
        iosContent
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macContent: some View {
        let tokens = theme.tokens(for: scheme)
        ZStack {
            tokens.background.color.ignoresSafeArea()
            switch viewModel.state {
            case .idle, .loading:
                ProgressView().tint(tokens.foregroundSecondary.color)
            case .empty:
                Text("No holdings")
                    .foregroundStyle(tokens.foregroundSecondary.color)
            case .error(let message):
                Text(message)
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            case .results(let positions):
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero(positions: positions)
                        donut
                        positionsTable(positions)
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Investments")
    }
    #endif

    #if os(iOS)
    private var iosContent: some View {
        let tokens = theme.tokens(for: scheme)
        return Group {
            switch viewModel.state {
            case .idle, .loading:
                ZStack { tokens.background.color; ProgressView() }
            case .empty:
                ZStack {
                    tokens.background.color
                    Text("No holdings")
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            case .error(let message):
                ZStack {
                    tokens.background.color
                    Text(message)
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            case .results(let positions):
                phonePositionsList(positions)
            }
        }
        .background(tokens.background.color.ignoresSafeArea())
        .navigationTitle("Investments")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh() }
    }

    private func phonePositionsList(_ positions: [InvestmentPosition]) -> some View {
        let tokens = theme.tokens(for: scheme)
        // Group by `SecurityKind` so a long stocks list is broken into
        // ETF / bond / cash sections — easier to scan than one flat list
        // on a 6.1-inch screen.
        let grouped = Dictionary(grouping: positions, by: \.kind)
        let kinds: [SecurityKind] = [.stock, .etf, .bond, .cash, .other]
            .filter { grouped[$0] != nil }
        return List {
            Section {
                hero(positions: positions)
                    .listRowBackground(tokens.surface.color)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }
            ForEach(kinds, id: \.self) { kind in
                Section {
                    ForEach(grouped[kind] ?? []) { position in
                        NavigationLink(value: position) {
                            phonePositionRow(position)
                        }
                        .listRowBackground(tokens.surface.color)
                    }
                } header: {
                    Text(kind.rawValue.uppercased())
                        .font(tokens.tickerFont(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func phonePositionRow(_ position: InvestmentPosition) -> some View {
        let tokens = theme.tokens(for: scheme)
        let pnl = position.unrealizedPnL ?? .zero
        let isGain = pnl >= .zero
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.ticker ?? "—")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(position.name ?? position.accountName)
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.value.formatted(.currency(code: position.currency)))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(pnl.formatted(.currency(code: position.currency)))
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(isGain ? tokens.gainAccent.color : tokens.lossAccent.color)
            }
        }
        .padding(.vertical, 4)
    }
    #endif

    private func hero(positions: [InvestmentPosition]) -> some View {
        let tokens = theme.tokens(for: scheme)
        let pnl = viewModel.unrealizedPnL
        let isGain = pnl >= .zero
        return VStack(alignment: .leading, spacing: 8) {
            Text("Portfolio")
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(viewModel.portfolioValue.formatted(.currency(code: "USD")))
                .font(tokens.tickerFont(size: 32, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            HStack(spacing: 14) {
                Text("Unrealized")
                    .font(tokens.tickerFont(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text(pnl.formatted(.currency(code: "USD")))
                    .font(tokens.tickerFont(size: 13, weight: .medium))
                    .foregroundStyle(isGain ? tokens.gainAccent.color : tokens.lossAccent.color)
                Text("\(positions.count) positions")
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tokens.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var donut: some View {
        let tokens = theme.tokens(for: scheme)
        let slices = viewModel.allocationByKind().map { slice in
            DonutSlice(
                id: slice.kind.rawValue,
                label: slice.kind.rawValue.capitalized,
                value: slice.value,
                percentage: slice.percentage,
                color: color(for: slice.kind)
            )
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Allocation")
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack(alignment: .top, spacing: 18) {
                AllocationDonutChart(slices: slices)
                    .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(slices) { slice in
                        HStack(spacing: 6) {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.label)
                                .font(tokens.ledgerRowFont)
                                .foregroundStyle(tokens.foregroundPrimary.color)
                            Spacer()
                            Text(String(format: "%.1f%%", NSDecimalNumber(decimal: slice.percentage).doubleValue))
                                .font(tokens.ledgerRowFont)
                                .foregroundStyle(tokens.foregroundSecondary.color)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(tokens.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func positionsTable(_ positions: [InvestmentPosition]) -> some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Positions")
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("TICKER").frame(width: 80, alignment: .leading)
                    Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                    Text("QTY").frame(width: 60, alignment: .trailing)
                    Text("PRICE").frame(width: 80, alignment: .trailing)
                    Text("VALUE").frame(width: 100, alignment: .trailing)
                    Text("PNL").frame(width: 100, alignment: .trailing)
                }
                .font(tokens.tickerFont(size: 9, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tokens.surface.color)
                ForEach(Array(positions.enumerated()), id: \.element.id) { index, position in
                    positionRow(position)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(index.isMultiple(of: 2)
                                    ? tokens.surface.color
                                    : tokens.ledgerStripe.color)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func positionRow(_ position: InvestmentPosition) -> some View {
        let tokens = theme.tokens(for: scheme)
        let pnl = position.unrealizedPnL ?? .zero
        let isGain = pnl >= .zero
        return HStack(spacing: 12) {
            Text(position.ticker ?? "—")
                .frame(width: 80, alignment: .leading)
                .font(tokens.tickerFont(size: 12, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(position.name ?? position.accountName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 11))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(1)
            Text(position.quantity.formatted(.number.precision(.fractionLength(0...4))))
                .frame(width: 60, alignment: .trailing)
                .font(tokens.tickerFont(size: 11))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(position.price.formatted(.currency(code: position.currency)))
                .frame(width: 80, alignment: .trailing)
                .font(tokens.tickerFont(size: 11))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(position.value.formatted(.currency(code: position.currency)))
                .frame(width: 100, alignment: .trailing)
                .font(tokens.tickerFont(size: 12, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(pnl.formatted(.currency(code: position.currency)))
                .frame(width: 100, alignment: .trailing)
                .font(tokens.tickerFont(size: 11, weight: .medium))
                .foregroundStyle(isGain ? tokens.gainAccent.color : tokens.lossAccent.color)
        }
    }

    private func color(for kind: SecurityKind) -> Color {
        let tokens = theme.tokens(for: scheme)
        switch kind {
        case .stock: return tokens.accent.color
        case .etf: return tokens.gainAccent.color
        case .bond: return tokens.foregroundSecondary.color
        case .cash: return tokens.gainAccent.color.opacity(0.4)
        case .other: return tokens.lossAccent.color.opacity(0.5)
        }
    }
}
