import SwiftUI
import Models
import DesignSystem

/// Ledger surface. macOS gets a sortable `Table`; iOS gets a `List` with
/// filter chips above the scroll. Both share the same row component so
/// money columns line up identically across platforms.
@MainActor
public struct FinanceTransactionsView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: FinanceTransactionsViewModel

    public init(viewModel: FinanceTransactionsViewModel) {
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
        iosLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return Group {
            switch viewModel.state {
            case .idle, .loading:
                ZStack { tokens.background.color; ProgressView().tint(tokens.foregroundSecondary.color) }
            case .empty:
                ZStack {
                    tokens.background.color
                    Text("No transactions")
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            case .error(let message):
                ZStack {
                    tokens.background.color
                    Text(message)
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            case .results(let rows):
                ledgerScrollMac(rows)
            }
        }
        .background(tokens.background.color)
        .navigationTitle("Transactions")
    }

    private func ledgerScrollMac(_ rows: [Models.Transaction]) -> some View {
        let tokens = theme.tokens(for: scheme)
        return ScrollView {
            VStack(spacing: 0) {
                ledgerHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(tokens.surface.color)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ledgerRow(row)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(index.isMultiple(of: 2)
                                    ? tokens.background.color
                                    : tokens.ledgerStripe.color)
                }
            }
        }
    }

    private var ledgerHeader: some View {
        let tokens = theme.tokens(for: scheme)
        return HStack(spacing: 12) {
            Text("DATE").frame(width: 84, alignment: .leading)
            Text("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
            Text("CATEGORY").frame(width: 140, alignment: .leading)
            Text("AMOUNT").frame(width: 110, alignment: .trailing)
        }
        .font(tokens.tickerFont(size: 9, weight: .semibold))
        .foregroundStyle(tokens.foregroundSecondary.color)
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack {
            tokens.background.color.ignoresSafeArea()
            VStack(spacing: 0) {
                chipsRow
                Group {
                    switch viewModel.state {
                    case .idle, .loading:
                        ProgressView()
                    case .empty:
                        Text("No transactions")
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    case .error(let message):
                        Text(message)
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    case .results(let rows):
                        List {
                            ForEach(rows) { row in
                                ledgerRow(row)
                                    .listRowBackground(tokens.surface.color)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $viewModel.filter.searchText, prompt: "Search ledger")
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Transactions")
    }

    @ViewBuilder
    private var chipsRow: some View {
        let tokens = theme.tokens(for: scheme)
        let allCategories = Array(Set(viewModel.rows.compactMap { row -> String? in
            if case .knownCategory(let s) = row.category { return s } else { return nil }
        })).sorted()
        if !allCategories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allCategories, id: \.self) { cat in
                        Button {
                            if viewModel.filter.categories.contains(cat) {
                                viewModel.filter.categories.remove(cat)
                            } else {
                                viewModel.filter.categories.insert(cat)
                            }
                        } label: {
                            Text(cat)
                                .font(tokens.tickerFont(size: 10, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(viewModel.filter.categories.contains(cat)
                                            ? tokens.accent.color.opacity(0.18)
                                            : tokens.surface.color)
                                .foregroundStyle(viewModel.filter.categories.contains(cat)
                                                 ? tokens.accent.color
                                                 : tokens.foregroundSecondary.color)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }
    #endif

    // MARK: - Row (shared)

    private func ledgerRow(_ row: Models.Transaction) -> some View {
        let tokens = theme.tokens(for: scheme)
        let isInflow = (row.amount ?? .zero) > .zero
        let guess = LocalStubCategorizationAPI.classify(
            name: row.name,
            fallback: row.category.displayLabel
        )
        return HStack(spacing: 12) {
            // Anomaly indicator — a thin caret leading edge for rows
            // whose absolute amount is unusually large for this dataset.
            // Cheap heuristic: |amount| > $250 for outflows.
            ZStack {
                if !row.pending, let a = row.amount, a < 0, -a > 250 {
                    Rectangle()
                        .fill(tokens.lossAccent.color)
                        .frame(width: 2)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 2)
                }
            }
            .frame(width: 2)
            Text(dayFormatter.string(from: row.date))
                .frame(width: 76, alignment: .leading)
                .font(tokens.tickerFont(size: 11))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .opacity(row.pending ? 0.5 : 1.0)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                if row.pending {
                    Text("PENDING")
                        .font(tokens.tickerFont(size: 8, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(row.pending ? 0.55 : 1.0)
            VStack(alignment: .leading, spacing: 3) {
                Text(guess.label)
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
                // Confidence bar — width scales with how sure the matcher is.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(tokens.foregroundSecondary.color.opacity(0.15))
                            .frame(height: 1.5)
                        Rectangle()
                            .fill(tokens.accent.color)
                            .frame(width: proxy.size.width * guess.confidence, height: 1.5)
                    }
                }
                .frame(height: 1.5)
            }
            .frame(width: 132, alignment: .leading)
            Text(formatMoney(row.amount, currency: row.currency))
                .frame(width: 110, alignment: .trailing)
                .font(tokens.tickerFont(size: 12, weight: .medium))
                .foregroundStyle(isInflow ? tokens.gainAccent.color : tokens.foregroundPrimary.color)
                .opacity(row.pending ? 0.55 : 1.0)
        }
    }

    private func formatMoney(_ value: Decimal?, currency: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency))
    }

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
}
