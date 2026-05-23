import SwiftUI
import Models
import DesignSystem

/// Accounts surface. macOS gets a sectioned `Table` keyed by `AccountKind`
/// so the user can sort by balance, mask, or institution. iOS gets a
/// grouped `List` with the same section structure and `.searchable`.
@MainActor
public struct FinanceAccountsView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: FinanceAccountsViewModel

    public init(viewModel: FinanceAccountsViewModel) {
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
                ZStack {
                    tokens.background.color
                    ProgressView().tint(tokens.foregroundSecondary.color)
                }
            case .empty:
                ZStack {
                    tokens.background.color
                    Text("No linked accounts")
                        .font(.system(size: 14))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            case .error(let message):
                ZStack {
                    tokens.background.color
                    VStack(spacing: 6) {
                        Text("Couldn't load accounts")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                        Text(message)
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                }
            case .results(let accounts):
                accountsTable(accounts)
            }
        }
        .background(tokens.background.color)
        .navigationTitle("Accounts")
    }

    private func accountsTable(_ accounts: [FinanceAccount]) -> some View {
        let tokens = theme.tokens(for: scheme)
        // Group by kind for sectioned rendering.
        let grouped = Dictionary(grouping: accounts, by: \.kind)
        let kinds = AccountKind.allCases.filter { grouped[$0] != nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                syncHealthCard(accounts: accounts)
                    .padding(.horizontal, 12)
                ForEach(kinds, id: \.self) { kind in
                    if let rows = grouped[kind] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind.rawValue.uppercased())
                                .font(tokens.tickerFont(size: 10, weight: .semibold))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                                .padding(.horizontal, 12)
                            VStack(spacing: 0) {
                                ForEach(rows) { account in
                                    accountTableRow(account)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(tokens.surface.color)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    @State private var hiddenAccountIds: Set<String> = []

    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return Group {
            switch viewModel.state {
            case .idle, .loading:
                ZStack { tokens.background.color; ProgressView() }
            case .empty:
                ZStack {
                    tokens.background.color
                    Text("No linked accounts")
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            case .error(let message):
                ZStack {
                    tokens.background.color
                    VStack(spacing: 6) {
                        Text("Couldn't load")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                        Text(message)
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                }
            case .results(let accounts):
                accountsGroupedList(accounts.filter { !hiddenAccountIds.contains($0.id) })
            }
        }
        .background(tokens.background.color)
        .searchable(text: $viewModel.searchText, prompt: "Search accounts")
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
    }

    /// iOS grouping intentionally keys on **institution** rather than
    /// account kind — on a phone, the user's mental model is "where is
    /// the money" (Chase, Fidelity, …), not "what type of account".
    /// The macOS table still groups by kind because its sortable column
    /// header carries the kind affordance.
    private func accountsGroupedList(_ accounts: [FinanceAccount]) -> some View {
        let tokens = theme.tokens(for: scheme)
        let grouped = Dictionary(grouping: accounts) { $0.institutionName ?? "Other" }
        let institutions = grouped.keys.sorted()
        return List {
            ForEach(institutions, id: \.self) { institution in
                Section {
                    ForEach(grouped[institution] ?? []) { account in
                        NavigationLink(value: account) {
                            accountTableRow(account)
                        }
                        .listRowBackground(tokens.surface.color)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                hiddenAccountIds.insert(account.id)
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                            .tint(.gray)
                            Button {
                                Task { await viewModel.refresh() }
                            } label: {
                                Label("Sync", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    HStack {
                        Text(institution.uppercased())
                            .font(tokens.tickerFont(size: 10, weight: .semibold))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                        Spacer()
                        Text("\(grouped[institution]?.count ?? 0)")
                            .font(tokens.tickerFont(size: 10))
                            .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
    #endif

    // MARK: - AI sync-health card

    /// One-line summary the operator reads first. Counts the institutions
    /// the user has linked and flags the action target (synapse-v2 web)
    /// rather than offering a re-link button in the native app — Plaid
    /// Link is web-owned.
    private func syncHealthCard(accounts: [FinanceAccount]) -> some View {
        InsightCard(insight: makeSyncHealthInsight(accounts: accounts))
    }

    private func makeSyncHealthInsight(accounts: [FinanceAccount]) -> Insight {
        let institutions = Set(accounts.compactMap(\.institutionName))
        if institutions.isEmpty {
            return Insight(
                id: "accounts.sync.health",
                kind: .narration,
                headline: "Sync health",
                body: "No linked institutions. Connect a bank in synapse-v2 to start syncing.",
                severity: .warning
            )
        }
        let inst = institutions.sorted().joined(separator: ", ")
        let count = institutions.count
        let plural = count == 1 ? "" : "s"
        return Insight(
            id: "accounts.sync.health",
            kind: .narration,
            headline: "Sync health",
            body: "\(count) institution\(plural) linked: \(inst). Re-link from synapse-v2 if a sync stalls.",
            severity: .info
        )
    }

    // MARK: - Row

    private func accountTableRow(_ account: FinanceAccount) -> some View {
        let tokens = theme.tokens(for: scheme)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
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
            Text(aiTagLabel(account.kind))
                .font(tokens.tickerFont(size: 9, weight: .semibold))
                .tracking(0.6)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(tokens.foregroundSecondary.color)
                .background(tokens.foregroundSecondary.color.opacity(0.10))
                .clipShape(Capsule())
            Text(formatMoney(account.currentBalance, currency: account.currency))
                .font(tokens.tickerFont(size: 12, weight: .medium))
                .foregroundStyle(
                    account.kind.isLiability ? tokens.lossAccent.color : tokens.foregroundPrimary.color
                )
        }
    }

    /// One-word AI tag for an account, displayed as a capsule next to
    /// the balance. Maps the Plaid taxonomy to the four buckets the
    /// brief asks for (Cash / Credit / Brokerage / Loan).
    private func aiTagLabel(_ kind: AccountKind) -> String {
        switch kind {
        case .checking, .savings: return "CASH"
        case .credit:             return "CREDIT"
        case .brokerage,
             .retirement:         return "BROKERAGE"
        case .loan:               return "LOAN"
        case .other:              return "OTHER"
        }
    }

    private func formatMoney(_ value: Decimal?, currency: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency))
    }
}
