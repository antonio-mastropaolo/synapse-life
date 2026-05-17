import SwiftUI
import Models
import DesignSystem

/// Ledger surface. macOS gets a sectioned ScrollView with sortable card
/// headers; iOS gets the same sectioned shape inside a List with
/// `.searchable`. Both platforms share the chip rail, the search field,
/// the pending-toggle, and the row component so columns line up
/// identically across platforms.
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
        return VStack(spacing: 0) {
            toolbarRow
            Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
            categoryChipsRow
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ZStack { tokens.background.color
                        ProgressView().tint(tokens.foregroundSecondary.color)
                    }
                case .error(let message):
                    ZStack {
                        tokens.background.color
                        Text(message)
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                case .ready(let groups):
                    if groups.isEmpty {
                        ZStack {
                            tokens.background.color
                            Text("No transactions")
                                .foregroundStyle(tokens.foregroundSecondary.color)
                        }
                    } else {
                        groupedScroll(groups)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(tokens.background.color)
        .navigationTitle("Transactions")
    }

    private func groupedScroll(_ groups: [CardGroup]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                    cardSection(group)
                }
            }
            .padding(.vertical, 4)
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack {
            tokens.background.color.ignoresSafeArea()
            VStack(spacing: 0) {
                toolbarRow
                categoryChipsRow
                Group {
                    switch viewModel.state {
                    case .idle, .loading:
                        ProgressView()
                    case .error(let message):
                        Text(message)
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    case .ready(let groups):
                        if groups.isEmpty {
                            Text("No transactions")
                                .foregroundStyle(tokens.foregroundSecondary.color)
                        } else {
                            List {
                                ForEach(groups) { group in
                                    Section {
                                        ForEach(group.transactions) { row in
                                            ledgerRow(row)
                                                .listRowBackground(tokens.surface.color)
                                                .listRowSeparator(.hidden)
                                        }
                                    } header: {
                                        sectionHeader(group)
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $viewModel.filter.searchText, prompt: "Search ledger")
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Transactions")
    }
    #endif

    // MARK: - Shared chrome

    /// Toolbar above the chip rail. On macOS we render a search field
    /// natively here; on iOS the system `.searchable` handles it. Both
    /// platforms expose the "Show pending" toggle in the same row.
    @ViewBuilder
    private var toolbarRow: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 12) {
            #if os(macOS)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                TextField("Search ledger", text: $viewModel.filter.searchText)
                    .textFieldStyle(.plain)
                    .font(tokens.tickerFont(size: 12))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tokens.surface.color)
            )
            .frame(maxWidth: 320, alignment: .leading)
            #endif
            Spacer(minLength: 0)
            // Label is drawn manually so we can use the tabular ticker
            // font that matches the rest of the chrome; the system Toggle
            // label uses the SF body font which would read out of place.
            HStack(spacing: 6) {
                Text("SHOW PENDING")
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Toggle("", isOn: $viewModel.filter.showPending)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Single-select category chips. The "All" chip clears the filter;
    /// tapping the active chip again also clears (toggle-off ergonomics).
    @ViewBuilder
    private var categoryChipsRow: some View {
        let tokens = theme.tokens(for: scheme)
        let cats = viewModel.availableCategories
        if !cats.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(
                        label: "All",
                        active: viewModel.selectedCategory == nil
                    ) {
                        viewModel.selectedCategory = nil
                    }
                    ForEach(cats, id: \.self) { cat in
                        chip(
                            label: cat,
                            active: viewModel.selectedCategory == cat
                        ) {
                            if viewModel.selectedCategory == cat {
                                viewModel.selectedCategory = nil
                            } else {
                                viewModel.selectedCategory = cat
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(tokens.background.color)
        }
    }

    @ViewBuilder
    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        let tokens = theme.tokens(for: scheme)
        Button(action: action) {
            Text(label)
                .font(tokens.tickerFont(size: 10, weight: active ? .bold : .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? tokens.accent.color.opacity(0.18) : tokens.surface.color)
                .foregroundStyle(active ? tokens.accent.color : tokens.foregroundSecondary.color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card section

    @ViewBuilder
    private func cardSection(_ group: CardGroup) -> some View {
        let tokens = theme.tokens(for: scheme)
        VStack(spacing: 0) {
            sectionHeader(group)
            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.18))
                .frame(height: 1)
            ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, row in
                ledgerRow(row)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(index.isMultiple(of: 2)
                                ? tokens.background.color
                                : tokens.ledgerStripe.color)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func sectionHeader(_ group: CardGroup) -> some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 8) {
            Text(group.account.cardSectionTitle)
                .font(tokens.tickerFont(size: 11, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("\(group.transactions.count)")
                .font(tokens.tickerFont(size: 9, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(tokens.foregroundSecondary.color.opacity(0.15))
                )
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tokens.surface.color)
    }

    // MARK: - Row (shared)

    private func ledgerRow(_ row: Models.Transaction) -> some View {
        let tokens = theme.tokens(for: scheme)
        let isInflow = (row.amount ?? .zero) > .zero
        // AI category guess + confidence — preserved from the AI-UI pass on
        // top of the worktree's sectioned-by-card structure. The confidence
        // bar paints inside the per-row category column.
        let guess = LocalStubCategorizationAPI.classify(
            name: row.name,
            fallback: row.category.displayLabel
        )
        let dimmed = row.pending
        let namePrimary = dimmed
            ? tokens.foregroundSecondary.color
            : tokens.foregroundPrimary.color
        let amountColor: Color = {
            if dimmed { return tokens.foregroundSecondary.color }
            return isInflow ? tokens.gainAccent.color : tokens.foregroundPrimary.color
        }()
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
                .frame(width: 64, alignment: .leading)
                .font(tokens.tickerFont(size: 11))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .opacity(row.pending ? 0.5 : 1.0)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(namePrimary)
                        .lineLimit(1)
                    if row.pending {
                        Text("PENDING")
                            .font(tokens.tickerFont(size: 8, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(tokens.foregroundSecondary.color.opacity(0.18))
                            )
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
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
                .monospacedDigit()
                .foregroundStyle(amountColor)
        }
        .opacity(dimmed ? 0.78 : 1.0)
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
