import SwiftUI
import Models
import DesignSystem
import SynnapseCharts

/// Personal finance hub. On macOS this is a three-column
/// `NavigationSplitView` — accounts sidebar / overview detail / inspector.
/// On iOS the same screen renders as a scrollable card stack: hero KPI,
/// allocation donut, sectioned account groups.
///
/// Carries the CockpitInstrument identity. Balances respect
/// `concealBalances` from the view model — when the OS reports the scene
/// has left active, every Decimal renders as a fixed-width row of bullets.
@MainActor
public struct FinancePersonalView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    @Bindable private var viewModel: FinancePersonalViewModel

    public init(viewModel: FinancePersonalViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .task {
                if case .idle = viewModel.state { await viewModel.refresh() }
            }
            .onChange(of: scenePhase) { _, new in
                viewModel.scenePhaseDidChange(new)
            }
            .privacySensitive(viewModel.concealBalances)
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
        NavigationSplitView {
            accountsSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            overview
                .navigationSplitViewColumnWidth(min: 420, ideal: 540)
                .navigationTitle("Personal")
        } detail: {
            inspector
        }
    }

    private var accountsSidebar: some View {
        let tokens = theme.tokens(for: scheme)
        let accounts: [FinanceAccount] = {
            if case .ready(let snap) = viewModel.state { return snap.accounts }
            return []
        }()
        return List(selection: Binding<FinanceAccount?>(
            get: { viewModel.selectedAccount },
            set: { viewModel.selectAccount($0) }
        )) {
            Section {
                ForEach(accounts) { account in
                    accountRow(account: account)
                        .tag(account)
                        .listRowBackground(tokens.surface.color)
                }
            } header: {
                Text("Accounts")
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(tokens.surface.color)
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack {
            tokens.background.color.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    netWorthHero
                        .padding(.horizontal, 16)
                    insightStrip
                        .padding(.horizontal, 16)
                    allocationCard
                        .padding(.horizontal, 16)
                    accountsList
                }
                .padding(.vertical, 16)
            }
            .refreshable { await viewModel.refresh() }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle("Personal")
        .navigationBarTitleDisplayMode(.large)
    }
    #endif

    // MARK: - Overview (middle column on macOS)

    @ViewBuilder
    private var overview: some View {
        let tokens = theme.tokens(for: scheme)
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                tokens.background.color
                ProgressView().tint(tokens.foregroundSecondary.color)
            }
            .accessibilityIdentifier("finance.personal.loading")
        case .error(let message):
            ZStack {
                tokens.background.color
                VStack(spacing: 6) {
                    Text("Couldn't load accounts")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(message)
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .accessibilityIdentifier("finance.personal.error")
        case .ready(let snapshot):
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    netWorthHero(snapshot: snapshot)
                    insightStrip
                    allocationCard(slices: snapshot.allocation)
                    Spacer(minLength: 4)
                }
                .padding(20)
            }
            .background(tokens.background.color)
        }
    }

    /// Horizontal strip of AI insight cards. The strip is read-only
    /// here — the VM refreshes the cards inside its own `refresh()`.
    @ViewBuilder
    private var insightStrip: some View {
        InsightStrip(
            insights: viewModel.insights.insights,
            isLoading: viewModel.insights.isLoading
        ) { insight in
            // Tap-to-account: if the insight names an account, route
            // there. The macOS shell observes `selectedAccount`.
            if let acctId = insight.accountId,
               case .ready(let snap) = viewModel.state,
               let match = snap.accounts.first(where: { $0.id == acctId }) {
                viewModel.selectAccount(match)
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var netWorthHero: some View {
        if case .ready(let snap) = viewModel.state {
            netWorthHero(snapshot: snap)
        } else {
            netWorthHeroPlaceholder
        }
    }

    private var netWorthHeroPlaceholder: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Net Worth")
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text("—")
                .font(tokens.tickerFont(size: 36, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tokens.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func netWorthHero(snapshot: FinancePersonalSnapshot) -> some View {
        let tokens = theme.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 8) {
            Text("Net Worth")
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(formatMoney(snapshot.netWorth, currency: "USD"))
                .font(tokens.tickerFont(size: 36, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .accessibilityLabel(viewModel.concealBalances ? "Balance concealed" : "Net worth")
            if let narration = viewModel.insights.insights.first(where: { $0.kind == .narration }) {
                NarrationLine(text: narration.body)
            }
            HStack(spacing: 18) {
                kpiCell(label: "Assets",
                        amount: snapshot.allocation
                            .filter { !$0.kind.isLiability }
                            .reduce(Decimal.zero) { $0 + $1.amount })
                kpiCell(label: "Liabilities",
                        amount: snapshot.allocation
                            .filter { $0.kind.isLiability }
                            .reduce(Decimal.zero) { $0 + abs($1.amount) },
                        tint: tokens.lossAccent.color)
                kpiCell(label: "Accounts",
                        rawText: "\(snapshot.accounts.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tokens.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func kpiCell(label: String, amount: Decimal? = nil, rawText: String? = nil, tint: Color? = nil) -> some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(tokens.tickerFont(size: 9, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(rawText ?? formatMoney(amount, currency: "USD"))
                .font(tokens.tickerFont(size: 14, weight: .medium))
                .foregroundStyle(tint ?? tokens.foregroundPrimary.color)
        }
    }

    @ViewBuilder
    private var allocationCard: some View {
        if case .ready(let snap) = viewModel.state {
            allocationCard(slices: snap.allocation)
        } else {
            EmptyView()
        }
    }

    private func allocationCard(slices: [AllocationSlice]) -> some View {
        let tokens = theme.tokens(for: scheme)
        let donutSlices = slices.map { slice in
            DonutSlice(
                id: slice.kind.rawValue,
                label: slice.kind.rawValue.capitalized,
                value: slice.amount,
                percentage: slice.percentage,
                color: color(for: slice.kind)
            )
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Allocation")
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack(alignment: .top, spacing: 18) {
                AllocationDonutChart(slices: donutSlices)
                    .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(donutSlices) { slice in
                        HStack(spacing: 6) {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.label)
                                .font(tokens.ledgerRowFont)
                                .foregroundStyle(tokens.foregroundPrimary.color)
                            Spacer()
                            Text("\(formatPercent(slice.percentage))")
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

    @ViewBuilder
    private var accountsList: some View {
        if case .ready(let snap) = viewModel.state {
            let tokens = theme.tokens(for: scheme)
            VStack(alignment: .leading, spacing: 6) {
                Text("Accounts")
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .padding(.horizontal, 16)
                #if os(iOS)
                VStack(spacing: 1) {
                    ForEach(Array(snap.accounts.enumerated()), id: \.element.id) { idx, account in
                        NavigationLink(value: account) {
                            accountRow(account: account)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(tokens.surface.color)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens account details")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                #else
                ForEach(snap.accounts) { account in
                    accountRow(account: account)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(tokens.surface.color)
                }
                #endif
            }
        }
    }

    private func accountRow(account: FinanceAccount) -> some View {
        let tokens = theme.tokens(for: scheme)
        return HStack(spacing: 10) {
            Circle()
                .fill(color(for: account.kind))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let inst = account.institutionName {
                        Text(inst)
                            .font(tokens.tickerFont(size: 10))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                    if let mask = account.mask {
                        Text("•• \(mask)")
                            .font(tokens.tickerFont(size: 10))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                }
            }
            Spacer()
            Text(formatMoney(account.currentBalance, currency: account.currency))
                .font(tokens.tickerFont(size: 12, weight: .medium))
                .foregroundStyle(
                    account.kind.isLiability ? tokens.lossAccent.color : tokens.foregroundPrimary.color
                )
                .accessibilityLabel(viewModel.concealBalances ? "Balance concealed" : "Balance \(account.currentBalance ?? 0)")
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        let tokens = theme.tokens(for: scheme)
        if let account = viewModel.selectedAccount {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(account.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    if let inst = account.institutionName {
                        Text(inst)
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                    Divider().overlay(tokens.foregroundSecondary.color.opacity(0.2))
                    LabeledRow(label: "Type", value: account.kind.rawValue.capitalized)
                    LabeledRow(label: "Currency", value: account.currency)
                    LabeledRow(label: "Current", value: formatMoney(account.currentBalance, currency: account.currency))
                    if let avail = account.availableBalance {
                        LabeledRow(label: "Available", value: formatMoney(avail, currency: account.currency))
                    }
                    if let limit = account.limitAmount {
                        LabeledRow(label: "Limit", value: formatMoney(limit, currency: account.currency))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(tokens.background.color)
        } else {
            ZStack {
                tokens.background.color
                Text("Select an account")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    // MARK: - Helpers

    private func formatMoney(_ value: Decimal?, currency: String) -> String {
        if viewModel.concealBalances {
            return "••••"
        }
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency))
    }

    private func formatPercent(_ value: Decimal) -> String {
        // value is 0...100; format with one decimal
        let n = NSDecimalNumber(decimal: value).doubleValue
        return String(format: "%.1f%%", n)
    }

    private func color(for kind: AccountKind) -> Color {
        let tokens = theme.tokens(for: scheme)
        switch kind {
        case .checking, .savings: return tokens.accent.color
        case .brokerage: return tokens.gainAccent.color
        case .retirement: return tokens.gainAccent.color.opacity(0.6)
        case .credit, .loan: return tokens.lossAccent.color
        case .other: return tokens.foregroundSecondary.color
        }
    }
}

private struct LabeledRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String
    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack {
            Text(label)
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            Text(value)
                .font(tokens.tickerFont(size: 12))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }
}
