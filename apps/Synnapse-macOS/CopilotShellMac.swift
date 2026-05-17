import SwiftUI
import AppKit
import DesignSystem
import Features
import Networking

/// macOS Copilot shell — the live shell the app boots into.
///
/// Replaces the previous `CockpitShellMac` chrome. The visual reference
/// is Copilot's main window (see `/tmp/copilot-ref/01-default.png`): a
/// dark sidebar at left with a brand wordmark, a search field, a flat
/// list of top-level rows (Dashboard, Transactions, Goals, Cash flow,
/// Accounts, Investments, Categories, Recurrings, plus the Synapse-
/// specific Subscriptions / Life / Advisors), a MY ACCOUNTS section
/// listing the user's accounts grouped by type, and a footer with Start
/// here / Get help / Settings.
///
/// Architecture: a flat `HStack` (sidebar + detail). We deliberately do
/// NOT use a top-level `NavigationSplitView` because the surviving
/// `FinancePersonalView` is itself a three-column split — nesting would
/// produce a four-column rendering that the brief explicitly does not
/// want. The shell carries routing in [[RootShellViewModel]]; each
/// detail surface owns its own internal navigation.
///
/// Detail wiring: top-level `.transactions` / `.accounts` /
/// `.investments` route through the existing FinancePersonalView family
/// because those surfaces already render the right content. New
/// destinations (`.dashboard`, `.goals`, `.cashFlow`, `.categories`,
/// `.recurrings`, `.subscriptions`) render a "coming up" placeholder
/// today — agents 2-5 swap in their feature views after merge.
@MainActor
struct CopilotShellMac: View {

    @Bindable var routing: RootShellViewModel

    let personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel
    let lifeAPI: LifeAPI
    let advisors: AdvisorsListViewModel

    /// Surfaced when DEBUG/demo mode is on so the user knows the
    /// figures are fixtures rather than live data.
    var showsDemoDataFooter: Bool = false

    var body: some View {
        let chrome = CopilotTokens.shell

        HStack(spacing: 0) {
            CopilotSidebar(
                routing: routing,
                chrome: chrome,
                showsDemoFooter: showsDemoDataFooter
            )
            .frame(width: 248)
            .background(chrome.sidebarBackground.color)

            Rectangle()
                .fill(chrome.separator.color)
                .frame(width: 1)

            CopilotDetailPane(
                routing: routing,
                personal: personal,
                accounts: accounts,
                transactions: transactions,
                investments: investments,
                lifeAPI: lifeAPI,
                advisors: advisors,
                chrome: chrome
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(chrome.contentBackground.color)
        }
        .foregroundStyle(chrome.foregroundPrimary.color)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sidebar

@MainActor
private struct CopilotSidebar: View {

    @Bindable var routing: RootShellViewModel
    let chrome: CopilotTokens.Shell
    var showsDemoFooter: Bool

    // Search field state — visual only for now. The text is preserved
    // across re-renders so the operator does not lose what they typed
    // when the destination changes (a small but real artisan
    // courtesy).
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    topLevelSection
                    myAccountsSection
                }
                .padding(.bottom, 18)
            }

            Spacer(minLength: 0)

            footer
        }
    }

    // MARK: Brand

    private var brandHeader: some View {
        HStack(spacing: 9) {
            // A small instrument-square mark — two squares slightly
            // offset, painted in the warm-yellow accent. Echoes the
            // Synapse brand against Copilot's chrome without copying
            // Copilot's actual mark.
            ZStack {
                Rectangle()
                    .stroke(chrome.foregroundSecondary.color.opacity(0.6), lineWidth: 1)
                    .frame(width: 14, height: 14)
                Rectangle()
                    .fill(chrome.brandAccent.color)
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: 2)
            }

            // SF Pro Display Medium 18pt — the brief's exact spec for
            // the wordmark. Subtle tracking gives the lowercase
            // letterforms breath without screaming.
            Text("Synapse")
                .font(.system(size: 18, weight: .medium, design: .default))
                .tracking(0.4)
                .foregroundStyle(chrome.foregroundPrimary.color)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(chrome.foregroundSecondary.color)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(chrome.foregroundPrimary.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(chrome.searchFieldFill.color)
        )
        .accessibilityIdentifier("copilot.sidebar.search")
    }

    // MARK: Top-level rows

    private var topLevelSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(CopilotSidebar.topLevelRows, id: \.destination) { row in
                CopilotNavRow(
                    label: row.label,
                    systemImage: row.icon,
                    badge: badge(for: row.destination),
                    isActive: routing.isActive(row.destination),
                    chrome: chrome
                ) {
                    routing.select(row.destination)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    /// Compile-time row metadata. Mirrors `RootDestination.canonicalOrder`
    /// — the test suite locks that contract so other agents can render
    /// content for these destinations and key off the order. Adding a
    /// new row requires the corresponding case on `RootDestination` and
    /// a baseline update.
    fileprivate static let topLevelRows: [RowSpec] = [
        .init(destination: .dashboard,    label: "Dashboard",    icon: "rectangle.grid.2x2"),
        .init(destination: .transactions, label: "Transactions", icon: "arrow.left.arrow.right"),
        .init(destination: .goals,        label: "Goals",        icon: "target"),
        .init(destination: .cashFlow,     label: "Cash flow",    icon: "waveform.path.ecg"),
        .init(destination: .accounts,     label: "Accounts",     icon: "building.columns"),
        .init(destination: .investments,  label: "Investments",  icon: "chart.pie"),
        .init(destination: .categories,   label: "Categories",   icon: "square.grid.3x3"),
        .init(destination: .recurrings,   label: "Recurrings",   icon: "arrow.triangle.2.circlepath"),
        .init(destination: .subscriptions, label: "Subscriptions", icon: "rectangle.stack"),
        .init(destination: .life,         label: "Life",         icon: "terminal"),
        .init(destination: .advisors,     label: "Advisors",     icon: "person.bubble")
    ]

    fileprivate struct RowSpec {
        let destination: RootDestination
        let label: String
        let icon: String
    }

    /// Badge value for a destination. Mocked at 0 for now — agent 2
    /// owns the live unreviewed-transactions count and will replace this
    /// when its Dashboard VM lands. Returning `nil` hides the badge so
    /// rows without a number stay clean.
    private func badge(for destination: RootDestination) -> Int? {
        switch destination {
        case .transactions: return 0
        default:            return nil
        }
    }

    // MARK: MY ACCOUNTS

    private var myAccountsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MY ACCOUNTS")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.9)
                .foregroundStyle(chrome.foregroundSecondary.color)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)

            accountSubgroup(
                title: "Credit cards",
                accounts: CopilotSidebar.mockCreditCards
            )

            accountSubgroup(
                title: "Depository",
                accounts: CopilotSidebar.mockDepositories
            )
        }
    }

    @ViewBuilder
    private func accountSubgroup(title: String, accounts: [MockAccount]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(chrome.foregroundSecondary.color.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(accounts) { account in
                CopilotAccountRow(
                    account: account,
                    isActive: routing.selectedAccountId == account.id,
                    chrome: chrome
                ) {
                    routing.select(account: account.id)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(chrome.separator.color)
                .frame(height: 1)
                .padding(.bottom, 8)

            CopilotFooterRow(label: "Start here", systemImage: "sparkles", chrome: chrome) {
                // Onboarding hook — owned by agent 5. Today this is a
                // no-op so the row is clickable without invoking any
                // half-built flow.
            }
            CopilotFooterRow(label: "Get help", systemImage: "questionmark.circle", chrome: chrome) {
                NSWorkspace.shared.open(URL(string: "https://synapse.tech/help")!)
            }
            CopilotFooterRowSettings(chrome: chrome)

            if showsDemoFooter {
                Text("demo data · sign in to sync")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(chrome.foregroundSecondary.color)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .accessibilityIdentifier("copilot.sidebar.demoDataFooter")
            }

            Text("v\(Bundle.main.copilotShortVersion) · Copilot Shell")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(chrome.foregroundSecondary.color.opacity(0.7))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 12)
        }
    }

    // MARK: Mock accounts

    fileprivate struct MockAccount: Identifiable {
        let id: String
        let label: String
        /// Optional dollar balance string. Copilot only paints the
        /// figure when it carries useful info; we mirror that by
        /// leaving the slot `nil` for accounts whose live VM has not
        /// emitted a balance yet.
        let balance: String?
        /// Optional colored swatch. The Discover row in the reference
        /// shows a small orange chip preceding the label; we lift the
        /// same affordance so credit-card brands are scannable.
        let swatch: Color?
    }

    fileprivate static let mockCreditCards: [MockAccount] = [
        .init(id: "discover-it",   label: "Discover It Card",  balance: "$1,053", swatch: .orange),
        .init(id: "paypal-credit", label: "PayPal Credit",     balance: nil,      swatch: .blue),
        .init(id: "platinum-visa", label: "Platinum Visa",     balance: nil,      swatch: .gray)
    ]

    fileprivate static let mockDepositories: [MockAccount] = [
        .init(id: "adv-plus-banking", label: "Adv Plus Banking",  balance: "$1,576", swatch: .red),
        .init(id: "paypal-balance",   label: "PayPal",            balance: nil,      swatch: .blue),
        .init(id: "advantage-savings", label: "Advantage Savings", balance: nil,      swatch: .red)
    ]
}

// MARK: - Top-level nav row

@MainActor
private struct CopilotNavRow: View {
    let label: String
    let systemImage: String
    let badge: Int?
    let isActive: Bool
    let chrome: CopilotTokens.Shell
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Left-edge accent bar — 2pt wide. Painted with the
                // brand accent so the active row tells the eye "this
                // is the live destination" at a glance.
                Rectangle()
                    .fill(isActive ? chrome.brandAccent.color : Color.clear)
                    .frame(width: 2)

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(
                        isActive
                            ? chrome.foregroundPrimary.color
                            : chrome.foregroundSecondary.color
                    )

                Text(label)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular, design: .default))
                    .foregroundStyle(
                        isActive || hover
                            ? chrome.foregroundPrimary.color
                            : chrome.foregroundSecondary.color
                    )

                Spacer()

                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(chrome.badgeForeground.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(chrome.badgeFill.color)
                        )
                        .accessibilityIdentifier("copilot.sidebar.badge.\(label)")
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0; cursor($0) }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : [.isButton])
    }

    private var rowBackground: Color {
        if isActive { return chrome.activeRowBackground.color }
        if hover    { return chrome.activeRowBackground.color.opacity(0.5) }
        return Color.clear
    }

    private func cursor(_ hovering: Bool) {
        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}

// MARK: - Account row

@MainActor
private struct CopilotAccountRow: View {
    let account: CopilotSidebar.MockAccount
    let isActive: Bool
    let chrome: CopilotTokens.Shell
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(isActive ? chrome.brandAccent.color : Color.clear)
                    .frame(width: 2)

                if let swatch = account.swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 8, height: 8)
                        .padding(.leading, 6)
                } else {
                    Color.clear.frame(width: 14)
                }

                Text(account.label)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(
                        isActive || hover
                            ? chrome.foregroundPrimary.color
                            : chrome.foregroundSecondary.color
                    )
                    .lineLimit(1)

                Spacer()

                if let balance = account.balance {
                    Text(balance)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(chrome.foregroundSecondary.color)
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? chrome.activeRowBackground.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0; if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .accessibilityLabel(account.label)
    }
}

// MARK: - Footer rows

@MainActor
private struct CopilotFooterRow: View {
    let label: String
    let systemImage: String
    let chrome: CopilotTokens.Shell
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(chrome.foregroundSecondary.color)
                Text(label)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(
                        hover
                            ? chrome.foregroundPrimary.color
                            : chrome.foregroundSecondary.color
                    )
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0; if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

/// Footer "Settings" row — uses the macOS 14+ `openSettings` action so
/// the system Settings scene (declared in `SynnapseMacApp`) opens in
/// place rather than this view drawing its own modal.
@MainActor
private struct CopilotFooterRowSettings: View {
    let chrome: CopilotTokens.Shell

    @Environment(\.openSettings) private var openSettings
    @State private var hover = false

    var body: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(chrome.foregroundSecondary.color)
                Text("Settings")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(
                        hover
                            ? chrome.foregroundPrimary.color
                            : chrome.foregroundSecondary.color
                    )
                Spacer()
                Text("Restart to update")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(chrome.foregroundSecondary.color.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0; if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

// MARK: - Detail pane

@MainActor
private struct CopilotDetailPane: View {

    @Bindable var routing: RootShellViewModel

    let personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel
    let lifeAPI: LifeAPI
    let advisors: AdvisorsListViewModel
    let chrome: CopilotTokens.Shell

    var body: some View {
        Group {
            switch routing.selection {
            // Surfaces with a live view today route to that view.
            case .transactions, .finance(.transactions):
                FinanceTransactionsView(viewModel: transactions)
                    .identity(.cockpitInstrument)
                    .id("transactions")

            case .accounts, .finance(.accounts):
                FinanceAccountsView(viewModel: accounts)
                    .identity(.cockpitInstrument)
                    .id("accounts")

            case .investments, .finance(.investments):
                FinanceInvestmentsView(viewModel: investments)
                    .identity(.cockpitInstrument)
                    .id("investments")

            case .finance(.personal):
                FinancePersonalView(viewModel: personal)
                    .identity(.cockpitInstrument)
                    .id("finance.personal")

            case .life:
                LifeTerminalScene(api: lifeAPI)
                    .identity(.terminalAmber)
                    .id("life")

            case .advisors:
                AdvisorsView(viewModel: advisors)
                    .identity(.cockpitInstrument)
                    .id("advisors")

            // Destinations owned by other agents — render a placeholder
            // until their feature views land. The placeholder is
            // identity-neutral so each surface inherits its own look on
            // wire-up.
            case .dashboard:
                CopilotPlaceholder(title: "Dashboard", subtitle: "Owned by agent 2 — coming up next.", chrome: chrome)
                    .id("dashboard")

            case .goals:
                CopilotPlaceholder(title: "Goals", subtitle: "Owned by agent 4 — coming up next.", chrome: chrome)
                    .id("goals")

            case .cashFlow:
                CopilotPlaceholder(title: "Cash flow", subtitle: "Owned by agent 4 — coming up next.", chrome: chrome)
                    .id("cashFlow")

            case .categories:
                CopilotPlaceholder(title: "Categories", subtitle: "Owned by agent 3 — coming up next.", chrome: chrome)
                    .id("categories")

            case .recurrings:
                CopilotPlaceholder(title: "Recurrings", subtitle: "Owned by agent 4 — coming up next.", chrome: chrome)
                    .id("recurrings")

            case .subscriptions:
                CopilotPlaceholder(title: "Subscriptions", subtitle: "Owned by agent 4 — coming up next.", chrome: chrome)
                    .id("subscriptions")
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: routing.selection)
    }
}

// MARK: - Placeholder

@MainActor
private struct CopilotPlaceholder: View {
    let title: String
    let subtitle: String
    let chrome: CopilotTokens.Shell

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .default))
                .foregroundStyle(chrome.foregroundPrimary.color)
            Text(subtitle)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(chrome.foregroundSecondary.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(40)
    }
}

// MARK: - Bundle helper

private extension Bundle {
    /// `CFBundleShortVersionString` from the hosting app's Info.plist.
    /// Named so it does not collide with the `shortVersion` extension
    /// the old `CockpitShellMac.swift` carried (now removed) if the
    /// build picks up a stale module map.
    var copilotShortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
