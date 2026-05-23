import SwiftUI
import Features
import Models
import DesignSystem
import Auth
import AppLifecycle

/// The "More" tab — the drill-down hub that holds everything that
/// didn't earn a primary slot on the Copilot-inspired bottom rail.
///
/// Ordering is product-first, not alphabetical:
///   * MONEY     — Personal, Accounts, Subscriptions, Recurrings
///   * LIFE      — Life terminal, Advisors
///   * SYSTEM    — Settings, Sign in
///
/// Each row drills into a real `NavigationLink` destination. Surfaces
/// that are still in progress (Goals, Categories, Cash flow) carry no
/// row in a shipping build — they would only show a placeholder, which
/// Apple review rejects. Those rows are mounted under DEBUG so the team
/// can reach the in-progress views locally.
@MainActor
struct MoreTab: View {

    let core: AppCore

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
                        LifeTerminalView(viewModel: core.life)
                            .navigationBarHidden(true)
                            .ignoresSafeArea(.container, edges: .top)
                            .identity(.terminalAmber)
                    } label: {
                        moreRow(symbol: "terminal", title: "Life",
                                subtitle: "Amber-phosphor daily log")
                    }
                    NavigationLink {
                        AdvisorsView(viewModel: core.advisors)
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
                            settings: core.settings,
                            auth: core.auth
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
            FinancePersonalView(viewModel: core.financePersonal)
                .identity(.cockpitInstrument)
        } label: {
            moreRow(symbol: "house.fill", title: "Personal",
                    subtitle: "Net worth and KPIs")
        }
        NavigationLink {
            FinanceAccountsView(viewModel: core.financeAccounts)
                .identity(.cockpitInstrument)
                .navigationDestination(for: FinanceAccount.self) { account in
                    AccountDetailView(
                        account: account,
                        financeAPI: core.financeAPI
                    )
                }
        } label: {
            moreRow(symbol: "creditcard.fill", title: "Accounts",
                    subtitle: "Linked institutions and balances")
        }
        #if DEBUG
        // Goals is in-progress (placeholder surface). Reachable only in
        // DEBUG so it never appears to a reviewer or shipping user.
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
        #endif
        NavigationLink {
            SubscriptionsView(viewModel: core.subscriptions)
                .navigationTitle("Subscriptions")
                .navigationBarTitleDisplayMode(.large)
                .identity(.cockpitInstrument)
        } label: {
            moreRow(symbol: "rectangle.stack", title: "Subscriptions",
                    subtitle: "All your recurring charges")
        }
        NavigationLink {
            RecurringsView(viewModel: core.recurrings)
                .navigationTitle("Recurrings")
                .navigationBarTitleDisplayMode(.large)
                .identity(.cockpitInstrument)
        } label: {
            moreRow(symbol: "arrow.clockwise", title: "Recurrings",
                    subtitle: "Predicted bills next month")
        }
        #if DEBUG
        // Categories editing is in-progress (placeholder surface).
        // Reachable only in DEBUG so it never appears to a reviewer.
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
        #endif
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
