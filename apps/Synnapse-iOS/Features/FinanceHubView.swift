import SwiftUI
import DesignSystem
import Features
import Models

/// Finance tab root for iOS. Renders four large drill-down cards rather
/// than the macOS three-column split. The hub also surfaces a compact
/// net-worth strip at the top so the user sees the headline KPI on tab
/// open without burning a tap on Personal first.
///
/// The hub deliberately does NOT embed the personal/accounts/transactions
/// surfaces; each is pushed via `NavigationLink` so the user always has a
/// real back stack and the large-title chrome belongs to the destination,
/// not the hub.
@MainActor
struct FinanceHubView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable var personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel

    enum Route: Hashable {
        case personal, accounts, transactions, investments
    }

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView {
            VStack(spacing: 16) {
                netWorthStrip
                    .padding(.horizontal, 16)
                cardGrid
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
        }
        .background(tokens.background.color.ignoresSafeArea())
        .navigationTitle("Finance")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .personal:
                FinancePersonalView(viewModel: personal)
            case .accounts:
                FinanceAccountsView(viewModel: accounts)
            case .transactions:
                FinanceTransactionsView(viewModel: transactions)
            case .investments:
                FinanceInvestmentsView(viewModel: investments)
            }
        }
        .refreshable {
            await personal.refresh()
            Haptics.refreshComplete()
        }
        .task {
            if case .idle = personal.state { await personal.refresh() }
        }
    }

    // MARK: - Net worth strip

    @ViewBuilder
    private var netWorthStrip: some View {
        let tokens = theme.tokens(for: scheme)
        if case .ready(let snap) = personal.state {
            VStack(alignment: .leading, spacing: 6) {
                Text("Net Worth")
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(formatMoney(snap.netWorth, currency: "USD", concealed: personal.concealBalances))
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .accessibilityLabel(personal.concealBalances ? "Balance concealed" : "Net worth")
                HStack(spacing: 14) {
                    miniKPI(label: "Accounts", value: "\(snap.accounts.count)")
                    miniKPI(label: "Holdings", value: investmentsCountText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tokens.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Net Worth")
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("—")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tokens.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func miniKPI(label: String, value: String) -> some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(tokens.tickerFont(size: 9, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }

    private var investmentsCountText: String {
        if case .results(let positions) = investments.state {
            return "\(positions.count)"
        }
        return "—"
    }

    // MARK: - Card grid

    private var cardGrid: some View {
        VStack(spacing: 12) {
            hubCard(.personal,
                    title: "Personal",
                    subtitle: "Net worth, allocation, KPIs",
                    symbol: "chart.pie.fill",
                    accent: theme.tokens(for: scheme).accent.color)
            hubCard(.accounts,
                    title: "Accounts",
                    subtitle: "Linked institutions and balances",
                    symbol: "creditcard.fill",
                    accent: theme.tokens(for: scheme).accent.color)
            hubCard(.transactions,
                    title: "Transactions",
                    subtitle: "Ledger, grouped by card",
                    symbol: "arrow.left.arrow.right",
                    accent: theme.tokens(for: scheme).accent.color)
            hubCard(.investments,
                    title: "Investments",
                    subtitle: "Holdings and unrealized P/L",
                    symbol: "chart.line.uptrend.xyaxis",
                    accent: theme.tokens(for: scheme).accent.color)
        }
    }

    private func hubCard(
        _ route: Route,
        title: String,
        subtitle: String,
        symbol: String,
        accent: Color
    ) -> some View {
        let tokens = theme.tokens(for: scheme)
        return NavigationLink(value: route) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(subtitle)
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.6))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(tokens.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.drillDown() })
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint("Opens \(title.lowercased()).")
    }

    private func formatMoney(_ value: Decimal?, currency: String, concealed: Bool) -> String {
        if concealed { return "••••" }
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency))
    }
}
