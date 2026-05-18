import SwiftUI
import Models
import DesignSystem
import SynnapseCharts

/// In-depth per-account drill-down. Hosted by the macOS shell when
/// `routing.selection == .accountDetail(id:)` resolves, and by the iOS
/// Accounts-list push. Cross-platform: no `import AppKit`/`UIKit` here
/// — platform-specific touches (cursor, navigation bar title) sit in
/// the host shells, not in the surface.
///
/// Layout matches the brief: a header (institution + balance), the
/// optional sync-error banner, a balance chart with range chips, a
/// KPI cluster, the scoped recent-transactions list (capped at 50),
/// and the recurrings section. On macOS we paint the right inspector
/// pane at >= 1280pt; on iOS we fold the inspector data into the
/// header (no horizontal room).
@MainActor
public struct AccountDetailView: View {

    @Bindable private var viewModel: AccountDetailViewModel
    private let chrome: CopilotTokens.Shell
    private let onSelectTransaction: ((Models.Transaction) -> Void)?

    public init(
        viewModel: AccountDetailViewModel,
        chrome: CopilotTokens.Shell = CopilotTokens.shell,
        onSelectTransaction: ((Models.Transaction) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.chrome = chrome
        self.onSelectTransaction = onSelectTransaction
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let error = viewModel.syncError { syncBanner(error) }
                balanceChartBlock
                kpiCluster
                recentTransactionsSection
                if !viewModel.recurrings.isEmpty { recurringsSection }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(chrome.contentBackground.color)
        .accessibilityIdentifier("accountDetail.\(viewModel.account.id)")
    }

    // MARK: - Header

    private var header: some View {
        let account = viewModel.account
        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(swatch(for: account.kind))
                        .frame(width: 10, height: 10)
                    Text(account.name)
                        .font(.system(size: 22, weight: .medium, design: .default))
                        .foregroundStyle(chrome.foregroundPrimary.color)
                }
                Text(subhead(for: account))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(chrome.foregroundSecondary.color)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMoney(account.currentBalance, currency: account.currency))
                    .font(.system(size: 32, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        account.kind.isLiability
                            ? Color.red.opacity(0.85)
                            : chrome.foregroundPrimary.color
                    )
                if let avail = account.availableBalance {
                    Text("Available · \(avail.formatted(.currency(code: account.currency)))")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(chrome.foregroundSecondary.color)
                }
            }
        }
    }

    /// "CHECKING · Chase · •• 4421 · Captured 2 days ago" — the
    /// inspector data folded into the header subline. Each segment is
    /// optional so we don't paint orphan separators.
    private func subhead(for account: FinanceAccount) -> String {
        var parts: [String] = [account.kind.rawValue.uppercased()]
        if let inst = account.institutionName { parts.append(inst) }
        if let mask = account.mask { parts.append("•• \(mask)") }
        if let days = viewModel.kpis.daysSinceCapture {
            switch days {
            case 0: parts.append("Captured today")
            case 1: parts.append("Captured yesterday")
            default: parts.append("Captured \(days) days ago")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Sync banner

    private func syncBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(chrome.foregroundPrimary.color)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .accessibilityIdentifier("accountDetail.syncBanner")
    }

    // MARK: - Balance chart

    private var balanceChartBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BALANCE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(chrome.foregroundSecondary.color)
                Spacer()
                rangeChips
            }
            chartView
                .frame(height: 220)
        }
    }

    private var rangeChips: some View {
        HStack(spacing: 6) {
            ForEach(AccountDetailBalanceSeries.Range.allCases, id: \.self) { range in
                Button {
                    viewModel.range = range
                } label: {
                    Text(range.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(
                            viewModel.range == range
                                ? chrome.foregroundPrimary.color
                                : chrome.foregroundSecondary.color
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    viewModel.range == range
                                        ? chrome.brandAccent.color.opacity(0.25)
                                        : chrome.activeRowBackground.color.opacity(0.4)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("accountDetail.range.\(range.label)")
            }
        }
    }

    private var chartView: some View {
        let points = viewModel.balanceSeries.map {
            MoneyTimePoint(date: $0.date, amount: $0.balance)
        }
        return MoneyLineChart(
            points: points,
            currency: viewModel.account.currency,
            accent: chrome.brandAccent.color
        )
    }

    // MARK: - KPIs

    private var kpiCluster: some View {
        // Two or three cards depending on whether monthIncome exists.
        let kpis = viewModel.kpis
        let currency = viewModel.account.currency
        return HStack(alignment: .top, spacing: 12) {
            kpiCard(
                label: "Spend this month",
                value: kpis.monthSpend.formatted(.currency(code: currency)),
                emphasis: chrome.foregroundPrimary.color
            )
            if let income = kpis.monthIncome {
                kpiCard(
                    label: "Income this month",
                    value: income.formatted(.currency(code: currency)),
                    emphasis: Color.green.opacity(0.9)
                )
            }
            kpiCard(
                label: "Avg daily spend",
                value: kpis.avgDailySpend.formatted(.currency(code: currency)),
                emphasis: chrome.foregroundPrimary.color
            )
        }
    }

    private func kpiCard(label: String, value: String, emphasis: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(chrome.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(emphasis)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(chrome.activeRowBackground.color.opacity(0.45))
        )
    }

    // MARK: - Recent transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(chrome.foregroundSecondary.color)
                Spacer()
                Text(transactionsCountLabel)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(chrome.foregroundSecondary.color)
            }
            if viewModel.scopedTransactions.isEmpty {
                emptyTransactions
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.scopedTransactions) { tx in
                        transactionRow(tx)
                        Divider()
                            .background(chrome.separator.color.opacity(0.4))
                    }
                }
            }
        }
    }

    private var transactionsCountLabel: String {
        let total = viewModel.allScopedTransactions.count
        let shown = viewModel.scopedTransactions.count
        if total > shown { return "\(shown) of \(total)" }
        return "\(total)"
    }

    private var emptyTransactions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No recent transactions on this account.")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(chrome.foregroundPrimary.color)
            Text("Charges will appear here as the ledger refreshes.")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(chrome.foregroundSecondary.color)
        }
        .padding(.vertical, 16)
    }

    private func transactionRow(_ tx: Models.Transaction) -> some View {
        let isInflow = (tx.amount ?? 0) > 0
        let amountColor: Color = isInflow
            ? Color.green.opacity(0.9)
            : chrome.foregroundPrimary.color
        return Button {
            onSelectTransaction?(tx)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.name)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(chrome.foregroundPrimary.color)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(Self.dayFormatter.string(from: tx.date))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(chrome.foregroundSecondary.color)
                        if tx.pending {
                            Text("PENDING")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(Color.orange.opacity(0.85))
                        }
                        if case .knownCategory(let label) = tx.category {
                            Text("· \(label)")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(chrome.foregroundSecondary.color)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                Text((tx.amount ?? 0).formatted(.currency(code: tx.currency)))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(amountColor)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelectTransaction == nil)
        .accessibilityIdentifier("accountDetail.tx.\(tx.id)")
    }

    // MARK: - Recurrings

    private var recurringsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECURRING ON THIS ACCOUNT")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(chrome.foregroundSecondary.color)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.recurrings) { rec in
                    recurringRow(rec)
                    Divider()
                        .background(chrome.separator.color.opacity(0.4))
                }
            }
        }
    }

    private func recurringRow(_ rec: DetectedRecurring) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.merchant)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(chrome.foregroundPrimary.color)
                    .lineLimit(1)
                Text(recurringSubline(rec))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(chrome.foregroundSecondary.color)
            }
            Spacer()
            Text("-\(rec.medianAmount.formatted(.currency(code: viewModel.account.currency)))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(chrome.foregroundPrimary.color)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .accessibilityIdentifier("accountDetail.recurring.\(rec.id)")
    }

    private func recurringSubline(_ rec: DetectedRecurring) -> String {
        let cadence: String
        switch rec.cadenceDays {
        case 7:   cadence = "Weekly"
        case 14:  cadence = "Bi-weekly"
        case 30:  cadence = "Monthly"
        case 90:  cadence = "Quarterly"
        case 365: cadence = "Annual"
        default:  cadence = "\(rec.cadenceDays)d"
        }
        return "\(cadence) · Next \(Self.dayFormatter.string(from: rec.predictedNext))"
    }

    // MARK: - Helpers

    private func swatch(for kind: AccountKind) -> Color {
        switch kind {
        case .credit:      return Color.orange.opacity(0.9)
        case .checking:    return Color.red.opacity(0.85)
        case .savings:     return Color.red.opacity(0.7)
        case .brokerage:   return Color.green.opacity(0.85)
        case .retirement:  return Color.green.opacity(0.55)
        case .loan:        return Color.gray
        case .other:       return Color.gray.opacity(0.7)
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

// MARK: - Host wrapper

/// Lifecycle-owning wrapper. Constructs an [[AccountDetailViewModel]]
/// for the resolved `id` inside `@State`, so mutations to the VM
/// (range chip taps) don't reset on parent re-renders. When the `id`
/// changes — operator switches accounts — the host's `.id()` modifier
/// on the call-site triggers a fresh subtree, `@State` resets, and a
/// new VM is built. Misses paint [[AccountDetailEmptyView]].
///
/// Hosted by the macOS shell's detail-pane switch and (in time) the
/// iOS Accounts-list push. Pure projection — the host doesn't fetch
/// anything; the shell passes the live accounts + transactions
/// slices down.
@MainActor
public struct AccountDetailHost: View {

    private let id: String
    private let accounts: [FinanceAccount]
    private let allTransactions: [Models.Transaction]
    private let chrome: CopilotTokens.Shell
    private let onSelectTransaction: ((Models.Transaction) -> Void)?

    @State private var viewModel: AccountDetailViewModel?

    public init(
        id: String,
        accounts: [FinanceAccount],
        allTransactions: [Models.Transaction],
        chrome: CopilotTokens.Shell = CopilotTokens.shell,
        onSelectTransaction: ((Models.Transaction) -> Void)? = nil
    ) {
        self.id = id
        self.accounts = accounts
        self.allTransactions = allTransactions
        self.chrome = chrome
        self.onSelectTransaction = onSelectTransaction
    }

    public var body: some View {
        Group {
            if let vm = viewModel {
                AccountDetailView(
                    viewModel: vm,
                    chrome: chrome,
                    onSelectTransaction: onSelectTransaction
                )
            } else {
                AccountDetailEmptyView(id: id, chrome: chrome)
            }
        }
        .task(id: id) {
            if let account = accounts.first(where: { $0.id == id }) {
                viewModel = AccountDetailViewModel(
                    account: account,
                    allTransactions: allTransactions
                )
            } else {
                viewModel = nil
            }
        }
    }
}

// MARK: - Account-not-found empty state

/// Rendered by the macOS shell when `.accountDetail(id:)` resolves to
/// an id the live VM doesn't know about. We paint a calm empty state
/// instead of crashing — preserves the brief's "no crash" requirement
/// and lets the operator pick a different account.
@MainActor
public struct AccountDetailEmptyView: View {

    private let id: String
    private let chrome: CopilotTokens.Shell

    public init(
        id: String,
        chrome: CopilotTokens.Shell = CopilotTokens.shell
    ) {
        self.id = id
        self.chrome = chrome
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account not found")
                .font(.system(size: 22, weight: .medium, design: .default))
                .foregroundStyle(chrome.foregroundPrimary.color)
            Text("The selected account is no longer in your ledger. Pick a different account from the sidebar.")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(chrome.foregroundSecondary.color)
            Text("Requested id: \(id)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(chrome.foregroundSecondary.color.opacity(0.7))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(40)
        .background(chrome.contentBackground.color)
        .accessibilityIdentifier("accountDetail.empty.\(id)")
    }
}
