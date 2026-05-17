import SwiftUI
import DesignSystem
import Features
import Models

/// Per-account drill-down. Pushed from the Accounts list. Shows the
/// account header (institution + mask), balance lines, and a recent
/// transaction tail scoped to the account via a dedicated
/// `FinanceTransactionsViewModel` instance.
///
/// The detail view owns its own transactions VM so the global ledger
/// (Transactions tab) and this per-account tail can refresh independently
/// without stepping on each other's pagination state.
@MainActor
struct AccountDetailView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let account: FinanceAccount
    let financeAPI: FinanceAPI

    @State private var ledger: FinanceTransactionsViewModel

    init(account: FinanceAccount, financeAPI: FinanceAPI) {
        self.account = account
        self.financeAPI = financeAPI
        // Account-scoped VM. The standard server contract honours
        // `accountId`; if the live API ignores the filter the list will
        // still render — it'll just include extra rows. That graceful
        // degradation matches the macOS inspector path.
        self._ledger = State(initialValue: FinanceTransactionsViewModel(
            api: financeAPI,
            accountId: account.id
        ))
    }

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        List {
            Section {
                balanceBlock
                    .listRowBackground(tokens.surface.color)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }
            Section("Recent activity") {
                switch ledger.state {
                case .idle, .loading:
                    HStack {
                        ProgressView()
                        Text("Loading…")
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                    .listRowBackground(tokens.surface.color)
                case .empty:
                    Text("No recent transactions")
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .listRowBackground(tokens.surface.color)
                case .error(let msg):
                    Text(msg)
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.lossAccent.color)
                        .listRowBackground(tokens.surface.color)
                case .results(let rows):
                    ForEach(rows.prefix(50), id: \.id) { row in
                        compactRow(row)
                            .listRowBackground(tokens.surface.color)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(tokens.background.color.ignoresSafeArea())
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await ledger.refresh()
            Haptics.refreshComplete()
        }
        .task {
            if case .idle = ledger.state { await ledger.refresh() }
        }
    }

    private var balanceBlock: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color(for: account.kind))
                    .frame(width: 8, height: 8)
                Text(account.kind.rawValue.uppercased())
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                if let inst = account.institutionName {
                    Text("·")
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text(inst)
                        .font(tokens.tickerFont(size: 10))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                if let mask = account.mask {
                    Text("·")
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text("•• \(mask)")
                        .font(tokens.tickerFont(size: 10))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            Text(formatMoney(account.currentBalance, currency: account.currency))
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .foregroundStyle(
                    account.kind.isLiability ? tokens.lossAccent.color : tokens.foregroundPrimary.color
                )
            if let avail = account.availableBalance {
                LabeledRow(label: "Available",
                           value: formatMoney(avail, currency: account.currency))
            }
            if let limit = account.limitAmount {
                LabeledRow(label: "Limit",
                           value: formatMoney(limit, currency: account.currency))
            }
        }
    }

    private func compactRow(_ row: Models.Transaction) -> some View {
        let tokens = theme.tokens(for: scheme)
        let isInflow = (row.amount ?? .zero) > .zero
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                Text(Self.dayFormatter.string(from: row.date))
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer(minLength: 8)
            Text((row.amount ?? 0).formatted(.currency(code: row.currency)))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isInflow ? tokens.gainAccent.color : tokens.foregroundPrimary.color)
        }
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

    private func formatMoney(_ value: Decimal?, currency: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
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
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }
}
