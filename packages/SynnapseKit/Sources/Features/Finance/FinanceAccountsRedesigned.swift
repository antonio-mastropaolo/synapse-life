import SwiftUI
import DesignSystem
import Models

/// Rich redesign of the Accounts surface, modelled on Copilot Money's
/// "Accounts" page and Monarch's accounts grid. Four stacked layers:
///
/// 1. **Hero summary** — page title plus three monospaced summary tiles
///    (net worth, total assets, total liabilities).
/// 2. **Sync attention banner** — surfaces when one or more accounts
///    look stale. The current `FinanceAccount` model does not carry a
///    per-account `lastSyncError`; that field lives upstream on
///    `ServerFinanceItem` and is dropped during projection. We
///    compensate by deriving a "needs attention" signal from
///    `balanceCapturedAt` — anything older than 48 hours is flagged.
/// 3. **Type-grouped section cards** — one rounded-rect card per
///    `AccountKind` family, each with an eyebrow header (count chip,
///    section total) and a vertical stack of clickable account rows.
///    Each row shows the institution logo, account name, mask, type
///    label, sync-status badge, current balance, and available balance.
///    Each section card carries its own "+ Add account" CTA.
/// 4. **Footer CTA** — a final primary "+ Add account" button outside
///    the section cards. Both CTAs route to the same placeholder
///    alert ("Account linking coming soon") — link UI is web-owned
///    today.
///
/// Empty state replaces all four layers with a single "Connect your
/// first account" card.
@MainActor
public struct FinanceAccountsRedesigned: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: FinanceAccountsViewModel

    /// Controls the "coming soon" alert wired to every Add-account CTA.
    @State private var showAddAccountAlert: Bool = false

    public init(viewModel: FinanceAccountsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header(tokens: tokens)
                if viewModel.accounts.isEmpty {
                    emptyState(tokens: tokens)
                } else {
                    if !attentionAccounts.isEmpty {
                        syncAttentionBanner(tokens: tokens)
                    }
                    sectionedCards(tokens: tokens)
                    footerCTA(tokens: tokens)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("finance.accounts.redesigned")
        .task {
            if case .idle = viewModel.state { await viewModel.refresh() }
        }
        .alert("Account linking coming soon", isPresented: $showAddAccountAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Plaid Link is currently web-owned. Open synapse-v2 in your browser to connect a new institution; the native client will pick it up on the next sync.")
        }
    }

    // MARK: - Header

    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accounts")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Every linked institution, grouped by what it is, with the balances Synapse last saw.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .padding(.bottom, 6)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                summaryTile(
                    label: "Net worth",
                    value: formatCurrency(netWorth),
                    tone: netWorth >= 0
                        ? tokens.foregroundPrimary.color
                        : tokens.lossAccent.color,
                    tokens: tokens
                )
                summaryTile(
                    label: "Total assets",
                    value: formatCurrency(totalAssets),
                    tone: tokens.foregroundPrimary.color,
                    tokens: tokens
                )
                summaryTile(
                    label: "Total liabilities",
                    value: formatCurrency(totalLiabilities),
                    tone: totalLiabilities > 0
                        ? tokens.lossAccent.color
                        : tokens.foregroundSecondary.color,
                    tokens: tokens
                )
                Spacer()
            }
        }
    }

    private func summaryTile(
        label: String,
        value: String,
        tone: Color,
        tokens: TokenSet
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(tone)
                .monospacedDigit()
        }
    }

    // MARK: - Sync attention banner

    private func syncAttentionBanner(tokens: TokenSet) -> some View {
        let amber = Color(red: 1.0, green: 0.69, blue: 0.22)
        let count = attentionAccounts.count
        let plural = count == 1 ? "" : "s"
        return HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) account\(plural) need attention")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Balances haven't refreshed in 48+ hours. Re-link the institution in synapse-v2 if syncs keep stalling.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text("View errors")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(amber)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(amber.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(amber.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Sectioned cards

    /// Display order — assets first (cash → investments), liabilities
    /// after, "Other" trailing as a catch-all.
    private static let sectionOrder: [AccountKindSection] = [
        .cashAndChecking,
        .investments,
        .creditCards,
        .loans,
        .other
    ]

    private func sectionedCards(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Self.sectionOrder) { section in
                let rows = accounts(in: section)
                if !rows.isEmpty {
                    sectionCard(section: section, rows: rows, tokens: tokens)
                }
            }
        }
    }

    private func sectionCard(
        section: AccountKindSection,
        rows: [FinanceAccount],
        tokens: TokenSet
    ) -> some View {
        let sectionTotal = rows.reduce(Decimal.zero) {
            $0 + ($1.currentBalance ?? 0)
        }
        return VStack(alignment: .leading, spacing: 0) {
            // Eyebrow header
            HStack(spacing: 10) {
                Circle()
                    .fill(section.tint)
                    .frame(width: 8, height: 8)
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("\(rows.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tokens.foregroundSecondary.color.opacity(0.12))
                    )
                Spacer()
                Text(formatCurrency(sectionTotal))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        section.isLiability
                            ? tokens.lossAccent.color
                            : tokens.foregroundPrimary.color
                    )
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(tokens.foregroundSecondary.color.opacity(0.10))

            VStack(spacing: 0) {
                ForEach(rows) { account in
                    accountRow(account, section: section, tokens: tokens)
                    if account.id != rows.last?.id {
                        Divider().background(tokens.foregroundSecondary.color.opacity(0.08))
                    }
                }
            }

            Divider().background(tokens.foregroundSecondary.color.opacity(0.10))

            // Per-section add CTA
            Button {
                showAddAccountAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add \(section.shortNoun) account")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(section.tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Row

    private func accountRow(
        _ account: FinanceAccount,
        section: AccountKindSection,
        tokens: TokenSet
    ) -> some View {
        AccountRow(
            account: account,
            section: section,
            tokens: tokens,
            isStale: isStale(account),
            onSelect: { viewModel.selected = account }
        )
    }

    /// Wrapped in its own struct so per-row hover state stays isolated
    /// — a single `@State` on the parent would re-render every row on
    /// each hover transition.
    private struct AccountRow: View {
        let account: FinanceAccount
        let section: AccountKindSection
        let tokens: TokenSet
        let isStale: Bool
        let onSelect: () -> Void

        @State private var isHovered: Bool = false

        var body: some View {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 14) {
                    MerchantLogoView(
                        merchant: account.institutionName ?? account.name,
                        fallbackColor: kindColor(account.kind),
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(account.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(tokens.foregroundPrimary.color)
                                .lineLimit(1)
                            if let mask = account.mask {
                                Text("•• \(mask)")
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(tokens.foregroundSecondary.color)
                            }
                        }
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(kindColor(account.kind))
                                    .frame(width: 6, height: 6)
                                Text(typeLabel(account.kind))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundStyle(tokens.foregroundSecondary.color)
                            }
                            syncBadge
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatMoney(account.currentBalance, currency: account.currency))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(
                                section.isLiability
                                    ? tokens.lossAccent.color
                                    : tokens.foregroundPrimary.color
                            )
                            .monospacedDigit()
                        if let avail = account.availableBalance {
                            Text("\(formatMoney(avail, currency: account.currency)) avail")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                        } else if let limit = account.limitAmount {
                            Text("\(formatMoney(limit, currency: account.currency)) limit")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color.opacity(isHovered ? 0.9 : 0.0))
                        .frame(width: 10)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    isHovered
                        ? tokens.foregroundSecondary.color.opacity(0.06)
                        : Color.clear
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
        }

        @ViewBuilder
        private var syncBadge: some View {
            if isStale {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Sync error")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                }
                .foregroundStyle(Color(red: 0.94, green: 0.33, blue: 0.56))
            } else if let captured = account.balanceCapturedAt {
                Text("Synced \(Self.formatRelative(captured))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            } else {
                Text("Awaiting first sync")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }

        private static func formatRelative(_ date: Date) -> String {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: date, relativeTo: Date())
        }
    }

    // MARK: - Footer CTA

    private func footerCTA(tokens: TokenSet) -> some View {
        Button {
            showAddAccountAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add account")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.27, green: 0.65, blue: 0.96))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Empty state

    private func emptyState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your first account")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Synapse pulls balances, transactions, and recurring charges from your linked institutions. Once you connect a bank, card, or brokerage in synapse-v2, it will appear here automatically.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showAddAccountAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Connect an account")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.27, green: 0.65, blue: 0.96))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Section taxonomy

    /// UI bucket. Multiple `AccountKind` cases can map into one bucket
    /// (e.g. `.brokerage` and `.retirement` both land in `.investments`).
    private enum AccountKindSection: String, Identifiable, CaseIterable {
        case cashAndChecking
        case creditCards
        case investments
        case loans
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cashAndChecking: return "Cash & checking"
            case .creditCards:     return "Credit cards"
            case .investments:     return "Investments"
            case .loans:           return "Loans"
            case .other:           return "Other"
            }
        }

        /// Singular noun used in the per-section "Add X account" CTA.
        var shortNoun: String {
            switch self {
            case .cashAndChecking: return "a cash"
            case .creditCards:     return "a credit card"
            case .investments:     return "an investment"
            case .loans:           return "a loan"
            case .other:           return "another"
            }
        }

        var isLiability: Bool {
            switch self {
            case .creditCards, .loans: return true
            default:                   return false
            }
        }

        /// Section header dot color. Picks a representative kind from
        /// the bucket so the palette stays in sync with row dots.
        var tint: Color {
            switch self {
            case .cashAndChecking: return kindColor(.checking)
            case .creditCards:     return kindColor(.credit)
            case .investments:     return kindColor(.brokerage)
            case .loans:           return kindColor(.loan)
            case .other:           return kindColor(.other)
            }
        }

        static func section(for kind: AccountKind) -> AccountKindSection {
            switch kind {
            case .checking, .savings:    return .cashAndChecking
            case .credit:                return .creditCards
            case .brokerage, .retirement: return .investments
            case .loan:                  return .loans
            case .other:                 return .other
            }
        }
    }

    private func accounts(in section: AccountKindSection) -> [FinanceAccount] {
        viewModel.accounts
            .filter { AccountKindSection.section(for: $0.kind) == section }
            .sorted { ($0.currentBalance ?? 0) > ($1.currentBalance ?? 0) }
    }

    // MARK: - Derived totals

    private var totalAssets: Decimal {
        viewModel.accounts.reduce(Decimal.zero) { running, account in
            guard !account.kind.isLiability else { return running }
            let balance = account.currentBalance ?? 0
            // Asset side: only count positive contributions.
            return running + (balance > 0 ? balance : 0)
        }
    }

    private var totalLiabilities: Decimal {
        // Liability balances come back as positive numbers from Plaid
        // (e.g. credit-card "current" balance is the amount owed).
        viewModel.accounts.reduce(Decimal.zero) { running, account in
            guard account.kind.isLiability else { return running }
            let balance = account.currentBalance ?? 0
            return running + max(balance, 0)
        }
    }

    private var netWorth: Decimal {
        totalAssets - totalLiabilities
    }

    // MARK: - Sync staleness

    /// Per-account "needs attention" signal. The native `FinanceAccount`
    /// model doesn't carry `lastSyncError` (that field lives on the
    /// server-side `ServerFinanceItem` envelope and is dropped during
    /// projection). As a stand-in we treat any balance older than 48h
    /// as stale; once the model gains an explicit error field, replace
    /// this with `account.lastSyncError != nil`.
    private func isStale(_ account: FinanceAccount) -> Bool {
        guard let captured = account.balanceCapturedAt else { return true }
        return Date().timeIntervalSince(captured) > 48 * 3600
    }

    private var attentionAccounts: [FinanceAccount] {
        viewModel.accounts.filter { isStale($0) }
    }

    // MARK: - Formatting helpers

    private func formatCurrency(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = (abs(amount) >= 1000) ? 0 : 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0"
    }

}

// MARK: - File-scope helpers (so the nested AccountRow struct can
// reach them without a parent reference).

func formatMoney(_ value: Decimal?, currency: String) -> String {
    guard let value else { return "—" }
    return value.formatted(.currency(code: currency))
}

// MARK: - Kind palette / labels (file-scope so the nested AccountRow
// struct can reach them without a parent reference).

private func kindColor(_ kind: AccountKind) -> Color {
    switch kind {
    case .checking:   return Color(red: 0.27, green: 0.65, blue: 0.96)
    case .savings:    return Color(red: 0.34, green: 0.78, blue: 0.50)
    case .credit:     return Color(red: 1.00, green: 0.69, blue: 0.22)
    case .brokerage:  return Color(red: 0.63, green: 0.42, blue: 0.84)
    case .retirement: return Color(red: 0.40, green: 0.85, blue: 0.95)
    case .loan:       return Color(red: 0.94, green: 0.33, blue: 0.56)
    case .other:      return Color(red: 0.58, green: 0.66, blue: 0.74)
    }
}

private func typeLabel(_ kind: AccountKind) -> String {
    switch kind {
    case .checking:   return "CHECKING"
    case .savings:    return "SAVINGS"
    case .credit:     return "CREDIT CARD"
    case .brokerage:  return "BROKERAGE"
    case .retirement: return "RETIREMENT"
    case .loan:       return "LOAN"
    case .other:      return "OTHER"
    }
}
