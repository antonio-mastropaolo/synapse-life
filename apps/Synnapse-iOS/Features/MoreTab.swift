import SwiftUI
import Features
import Models
import DesignSystem
import Auth

/// The "More" tab — the drill-down hub that holds everything that
/// didn't earn a primary slot on the Copilot-inspired bottom rail.
///
/// Ordering is product-first, not alphabetical:
///   * MONEY     — Personal, Accounts, Goals, Subscriptions,
///                 Recurrings, Categories
///   * LIFE      — Life terminal, Advisors
///   * SYSTEM    — Settings, Sign in
///
/// Each row drills into a `NavigationLink` destination — for the
/// surfaces that exist today (Personal, Accounts, Life, Advisors,
/// Settings) we push the real view; for the surfaces other agents
/// still own (Goals, Subscriptions, Recurrings, Categories, Cash
/// flow) we surface a `ComingSoonView` so the tab is exhaustive
/// rather than misleading.
@MainActor
struct MoreTab: View {

    let appModel: AppModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            List {
                Section("Money") {
                    moneyRows
                }
                Section("Life") {
                    NavigationLink {
                        LifeTerminalView(viewModel: appModel.life)
                            .navigationBarHidden(true)
                            .ignoresSafeArea(.container, edges: .top)
                            .identity(.terminalAmber)
                    } label: {
                        moreRow(symbol: "terminal", title: "Life",
                                subtitle: "Amber-phosphor daily log")
                    }
                    NavigationLink {
                        AdvisorsView(viewModel: appModel.advisors)
                            .navigationTitle("Advisors")
                            .navigationBarTitleDisplayMode(.large)
                            .identity(.cockpitInstrument)
                    } label: {
                        moreRow(symbol: "person.bubble", title: "Advisors",
                                subtitle: "5 financial advisors on call")
                    }
                }
                Section("System") {
                    NavigationLink {
                        SettingsForm(
                            settings: appModel.settings,
                            auth: appModel.auth
                        )
                        .identity(.editorial)
                    } label: {
                        moreRow(symbol: "gearshape", title: "Settings",
                                subtitle: "Preferences and account")
                    }
                }
            }
            .navigationTitle("More")
        }
    }

    @ViewBuilder
    private var moneyRows: some View {
        NavigationLink {
            FinancePersonalView(viewModel: appModel.financePersonal)
                .identity(.cockpitInstrument)
        } label: {
            moreRow(symbol: "house.fill", title: "Personal",
                    subtitle: "Net worth and KPIs")
        }
        NavigationLink {
            FinanceAccountsView(viewModel: appModel.financeAccounts)
                .identity(.cockpitInstrument)
                .navigationDestination(for: FinanceAccount.self) { account in
                    AccountDetailView(
                        account: account,
                        financeAPI: appModel.financeAPI
                    )
                }
        } label: {
            moreRow(symbol: "creditcard.fill", title: "Accounts",
                    subtitle: "Linked institutions and balances")
        }
        NavigationLink {
            ComingSoonView(
                title: "Goals",
                subtitle: "Track monthly savings against targets",
                symbol: "target"
            )
        } label: {
            moreRow(symbol: "target", title: "Goals",
                    subtitle: "Savings targets")
        }
        NavigationLink {
            ComingSoonView(
                title: "Subscriptions",
                subtitle: "Recurring SaaS and streaming charges",
                symbol: "rectangle.stack"
            )
        } label: {
            moreRow(symbol: "rectangle.stack", title: "Subscriptions",
                    subtitle: "All your recurring charges")
        }
        NavigationLink {
            ComingSoonView(
                title: "Recurrings",
                subtitle: "Predicted upcoming charges",
                symbol: "arrow.clockwise"
            )
        } label: {
            moreRow(symbol: "arrow.clockwise", title: "Recurrings",
                    subtitle: "Predicted bills next month")
        }
        NavigationLink {
            ComingSoonView(
                title: "Categories",
                subtitle: "Edit category rules and re-tag rows",
                symbol: "tag"
            )
        } label: {
            moreRow(symbol: "tag", title: "Categories",
                    subtitle: "Rules and tagging")
        }
    }

    @ViewBuilder
    private func moreRow(symbol: String, title: String, subtitle: String) -> some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.accent.color.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.accent.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .padding(.vertical, 2)
    }
}
