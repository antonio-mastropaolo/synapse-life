import SwiftUI
import Features
import DesignSystem

/// macOS Finance shell. The Personal surface already has its own
/// NavigationSplitView for accounts/inspector, so we use a top-level
/// sidebar to switch between the four screens (Personal, Accounts,
/// Transactions, Investments). Each screen reuses the cross-platform
/// SwiftUI view from SynapseKit.
@MainActor
struct FinanceShellView: View {

    enum Surface: String, Hashable, CaseIterable, Identifiable {
        case personal, accounts, transactions, investments
        var id: Self { self }
        var title: String {
            switch self {
            case .personal: return "Personal"
            case .accounts: return "Accounts"
            case .transactions: return "Transactions"
            case .investments: return "Investments"
            }
        }
        var systemImage: String {
            switch self {
            case .personal: return "house"
            case .accounts: return "list.bullet.rectangle"
            case .transactions: return "arrow.left.arrow.right"
            case .investments: return "chart.pie"
            }
        }
    }

    let personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel

    @State private var selection: Surface

    init(
        personal: FinancePersonalViewModel,
        accounts: FinanceAccountsViewModel,
        transactions: FinanceTransactionsViewModel,
        investments: FinanceInvestmentsViewModel,
        initialSurface: Surface
    ) {
        self.personal = personal
        self.accounts = accounts
        self.transactions = transactions
        self.investments = investments
        _selection = State(initialValue: initialSurface)
    }

    var body: some View {
        NavigationSplitView {
            List(Surface.allCases, selection: $selection) { surface in
                Label(surface.title, systemImage: surface.systemImage)
                    .tag(surface)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("Finance")
        } detail: {
            switch selection {
            case .personal: FinancePersonalView(viewModel: personal)
            case .accounts: FinanceAccountsView(viewModel: accounts)
            case .transactions: FinanceTransactionsView(viewModel: transactions)
            case .investments: FinanceInvestmentsView(viewModel: investments)
            }
        }
    }
}
