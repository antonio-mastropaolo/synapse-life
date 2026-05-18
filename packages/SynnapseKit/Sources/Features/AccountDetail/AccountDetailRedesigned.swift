import SwiftUI
import Models
import DesignSystem
import SynnapseCharts

/// Redesigned per-account detail surface for the macOS shell.
///
/// Inspired by Copilot Money's account drill-down and Monarch's account
/// page: a tall hero with the institution glyph and the live balance, a
/// range-selectable balance chart, a four-tile KPI strip, and three
/// stacked slots reserved for the AI insights panel, the transactions
/// feed, and the sync status card (delivered by sibling agents in
/// `Features/AccountDetail/`).
///
/// The surface consumes the existing `AccountDetailViewModel` directly —
/// no new projection layer — so range chip taps round-trip through the
/// VM's `range` binding and the balance walk recomputes deterministically.
@MainActor
public struct AccountDetailRedesigned: View {

    @Bindable private var viewModel: AccountDetailViewModel
    private let onClose: () -> Void
    private let chrome: CopilotTokens.Shell

    public init(
        viewModel: AccountDetailViewModel,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.chrome = CopilotTokens.shell
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                hero
                balanceChartBlock
                kpiStrip
                // AccountInsightsPanel slot — to be wired by integrator
                // once B1 ships its public type. The stub Text below
                // marks the layout slot so this surface paints with
                // realistic vertical rhythm during individual builds.
                insightsPanelSlot
                // AccountTransactionsFeed slot — owned by B2.
                transactionsFeedSlot
                // AccountSyncStatusCard slot — owned by B3.
                syncStatusSlot
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(chrome.contentBackground.color)
        .accessibilityIdentifier("accountDetailRedesigned.\(viewModel.account.id)")
    }

    // MARK: - Hero
    //
    // 64pt institution logo · account name (24pt semibold) · type / mask
    // / sync subline · big balance on the right (32pt monospaced, red on
    // liabilities) · close X.

    private var hero: some View {
        let account = viewModel.account
        let isLiability = account.kind.isLiability
        return HStack(alignment: .top, spacing: 20) {
            MerchantLogoView(
                merchant: account.institutionName ?? account.name,
                fallbackColor: swatch(for: account.kind),
                size: 64
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(account.name)
                    .font(.system(size: 24, weight: .semibold, design: .default))
                    .foregroundStyle(chrome.foregroundPrimary.color)
                    .lineLimit(1)
                Text(heroSubline(for: account))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(chrome.foregroundSecondary.color)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatMoney(account.currentBalance, currency: account.currency))
                    .font(.system(size: 32, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        isLiability
                            ? Color.red.opacity(0.85)
                            : chrome.foregroundPrimary.color
                    )
                    .monospacedDigit()
                if let available = account.availableBalance {
                    Text("Available · \(available.formatted(.currency(code: account.currency)))")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(chrome.foregroundSecondary.color)
                }
            }
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(chrome.foregroundSecondary.color)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(chrome.activeRowBackground.color.opacity(0.45))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("accountDetailRedesigned.close")
        .help("Close")
    }

    /// "CHECKING · Chase · •• 4421 · Synced 2h ago" — built from the
    /// account fields plus the VM's `daysSinceCapture` KPI. We collapse
    /// "0 days" into "Synced today" and "1 day" into "Synced yesterday"
    /// so the line reads naturally.
    private func heroSubline(for account: FinanceAccount) -> String {
        var parts: [String] = [account.kind.rawValue.uppercased()]
        if let institution = account.institutionName {
            parts.append(institution)
        }
        if let mask = account.mask {
            parts.append("•• \(mask)")
        }
        if let label = syncedLabel(for: account) {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }

    /// Renders the "Synced Xh ago" / "Synced today" trailing segment.
    /// Returns `nil` when the account has never captured a balance so
    /// we don't paint an orphan separator.
    private func syncedLabel(for account: FinanceAccount) -> String? {
        guard let captured = account.balanceCapturedAt else { return nil }
        let elapsed = viewModel.today.timeIntervalSince(captured)
        if elapsed < 60 {
            return "Synced just now"
        }
        if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "Synced \(minutes)m ago"
        }
        if elapsed < 86_400 {
            let hours = Int(elapsed / 3600)
            return "Synced \(hours)h ago"
        }
        guard let days = viewModel.kpis.daysSinceCapture else { return nil }
        switch days {
        case 0: return "Synced today"
        case 1: return "Synced yesterday"
        default: return "Synced \(days)d ago"
        }
    }

    // MARK: - Balance chart with range chips

    private var balanceChartBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("BALANCE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(chrome.foregroundSecondary.color)
                Spacer()
                rangeChips
            }
            chartView
                .frame(height: 240)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chrome.activeRowBackground.color.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(chrome.separator.color.opacity(0.35), lineWidth: 0.5)
        )
    }

    private var rangeChips: some View {
        HStack(spacing: 6) {
            ForEach(AccountDetailBalanceSeries.Range.allCases, id: \.self) { range in
                Button {
                    viewModel.range = range
                } label: {
                    Text(range.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(
                            viewModel.range == range
                                ? chrome.foregroundPrimary.color
                                : chrome.foregroundSecondary.color
                        )
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    viewModel.range == range
                                        ? chrome.brandAccent.color.opacity(0.28)
                                        : chrome.activeRowBackground.color.opacity(0.4)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("accountDetailRedesigned.range.\(range.label)")
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

    // MARK: - KPI strip (four tiles)
    //
    // Spend · Income · Avg daily · Days since capture. Income card hides
    // entirely on liability accounts (the VM returns `nil`); we keep the
    // strip at four tiles by surfacing "Limit" on credit cards as the
    // fallback when a limit exists.

    private var kpiStrip: some View {
        let kpis = viewModel.kpis
        let currency = viewModel.account.currency
        return HStack(alignment: .top, spacing: 12) {
            statTile(
                label: "Spend this month",
                value: kpis.monthSpend.formatted(.currency(code: currency)),
                emphasis: chrome.foregroundPrimary.color
            )
            if let income = kpis.monthIncome {
                statTile(
                    label: "Income this month",
                    value: income.formatted(.currency(code: currency)),
                    emphasis: Color.green.opacity(0.9)
                )
            } else if let limit = viewModel.account.limitAmount {
                statTile(
                    label: "Credit limit",
                    value: limit.formatted(.currency(code: currency)),
                    emphasis: chrome.foregroundPrimary.color
                )
            } else {
                statTile(
                    label: "Income this month",
                    value: "—",
                    emphasis: chrome.foregroundSecondary.color
                )
            }
            statTile(
                label: "Avg daily spend",
                value: kpis.avgDailySpend.formatted(.currency(code: currency)),
                emphasis: chrome.foregroundPrimary.color
            )
            statTile(
                label: "Days since capture",
                value: daysCapturedLabel(kpis.daysSinceCapture),
                emphasis: chrome.foregroundPrimary.color
            )
        }
    }

    private func daysCapturedLabel(_ days: Int?) -> String {
        guard let days else { return "—" }
        switch days {
        case 0: return "Today"
        case 1: return "1 day"
        default: return "\(days) days"
        }
    }

    private func statTile(label: String, value: String, emphasis: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(chrome.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(emphasis)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chrome.activeRowBackground.color.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(chrome.separator.color.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Sibling-agent slots
    //
    // Each slot below is a placeholder card sized roughly like the real
    // surface so the redesigned layout reads as finished during the
    // individual-build phase. The integrator will swap each `Text(...)`
    // for the real view once B1/B2/B3 land their public types.

    private var insightsPanelSlot: some View {
        AccountInsightsPanel(viewModel: viewModel)
            .accessibilityIdentifier("accountDetailRedesigned.slot.insights")
    }

    private var transactionsFeedSlot: some View {
        AccountTransactionsFeed(viewModel: viewModel)
            .accessibilityIdentifier("accountDetailRedesigned.slot.transactions")
    }

    private var syncStatusSlot: some View {
        AccountSyncStatusCard(viewModel: viewModel)
            .accessibilityIdentifier("accountDetailRedesigned.slot.sync")
    }

    private func slotCard(kicker: String, stub: Text) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kicker)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(chrome.foregroundSecondary.color)
            stub
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(chrome.foregroundSecondary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 18)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chrome.activeRowBackground.color.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(chrome.separator.color.opacity(0.25), lineWidth: 0.5)
        )
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
}

// MARK: - Empty state

/// Defensive fallback rendered when the caller hands us a `nil`-like
/// view-model anchor. The brief promises the redesigned surface
/// always survives a missing account.
@MainActor
public struct AccountDetailRedesignedEmpty: View {

    private let onClose: () -> Void
    private let chrome: CopilotTokens.Shell

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.chrome = CopilotTokens.shell
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Account not found")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(chrome.foregroundPrimary.color)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(chrome.foregroundSecondary.color)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(chrome.activeRowBackground.color.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
            }
            Text("The selected account is no longer in your ledger. Pick a different account from the sidebar.")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(chrome.foregroundSecondary.color)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(chrome.contentBackground.color)
        .accessibilityIdentifier("accountDetailRedesigned.empty")
    }
}
