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
    @State private var scope: LedgerStatusScope = .all
    @State private var collapsedAccountIds: Set<String> = []

    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack {
            tokens.background.color.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) {
                    Text("All").tag(LedgerStatusScope.all)
                    Text("Pending").tag(LedgerStatusScope.pending)
                    Text("Posted").tag(LedgerStatusScope.posted)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

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
                        groupedByCardList(scope.apply(to: rows))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $viewModel.filter.searchText, prompt: "Search ledger")
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Groups rows by `accountName` (falling back to `accountId` then
    /// "Unknown") and renders them as collapsible sections. The grouping
    /// itself is a pure function in `LedgerFilter.swift` so its ordering
    /// can be unit-tested without spinning up SwiftUI.
    private func groupedByCardList(_ rows: [Models.Transaction]) -> some View {
        let tokens = theme.tokens(for: scheme)
        let sections = groupTransactionsByCard(rows)
        return List {
            ForEach(sections, id: \.card) { section in
                let card = section.card
                let cardRows = section.rows
                let collapsed = collapsedAccountIds.contains(card)
                Section {
                    if !collapsed {
                        ForEach(cardRows) { row in
                            NavigationLink(value: row) {
                                phoneLedgerRow(row)
                            }
                            .listRowBackground(tokens.surface.color)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if collapsed {
                                collapsedAccountIds.remove(card)
                            } else {
                                collapsedAccountIds.insert(card)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                            Text(card.uppercased())
                                .font(tokens.tickerFont(size: 10, weight: .semibold))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                            Spacer()
                            Text("\(cardRows.count)")
                                .font(tokens.tickerFont(size: 10))
                                .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(card), \(cardRows.count) transactions")
                    .accessibilityHint(collapsed ? "Tap to expand" : "Tap to collapse")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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

    /// Phone-tuned ledger row. The shared `ledgerRow` uses fixed-pixel
    /// column widths because the macOS table needs aligned columns; on a
    /// 402-pt iPhone width those widths blow past the trailing edge.
    /// This variant uses an `HStack` with a flexible centre column and
    /// trailing-aligned amount, so the row fits Dynamic Type up to
    /// Accessibility Large without truncating the merchant name.
    private func phoneLedgerRow(_ row: Models.Transaction) -> some View {
        let tokens = theme.tokens(for: scheme)
        let isInflow = (row.amount ?? .zero) > .zero
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(dayFormatter.string(from: row.date))
                        .font(tokens.tickerFont(size: 10))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    if row.pending {
                        Text("PENDING")
                            .font(tokens.tickerFont(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(tokens.foregroundSecondary.color.opacity(0.12))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                            .clipShape(Capsule())
                    }
                    Text(row.category.displayLabel)
                        .font(tokens.tickerFont(size: 10))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text((row.amount ?? 0).formatted(.currency(code: row.currency)))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(isInflow ? tokens.gainAccent.color : tokens.foregroundPrimary.color)
        }
        .padding(.vertical, 4)
    }
    #endif

    // MARK: - Row (shared)

    private func ledgerRow(_ row: Models.Transaction) -> some View {
        let tokens = theme.tokens(for: scheme)
        let isInflow = (row.amount ?? .zero) > .zero
        return HStack(spacing: 12) {
            Text(dayFormatter.string(from: row.date))
                .frame(width: 84, alignment: .leading)
                .font(tokens.tickerFont(size: 11))
                .foregroundStyle(tokens.foregroundSecondary.color)
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
            Text(row.category.displayLabel)
                .frame(width: 140, alignment: .leading)
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(1)
            Text(formatMoney(row.amount, currency: row.currency))
                .frame(width: 110, alignment: .trailing)
                .font(tokens.tickerFont(size: 12, weight: .medium))
                .foregroundStyle(isInflow ? tokens.gainAccent.color : tokens.foregroundPrimary.color)
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
