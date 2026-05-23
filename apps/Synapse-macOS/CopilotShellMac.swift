import SwiftUI
import AppKit
import DesignSystem
import Features
import Models
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
    // New (2026-05-17 Copilot integration) — dashboard inbox + AI++
    // surfaces. These are owned by `AppCore` so the sidebar can route
    // the new destinations through their real VMs instead of
    // placeholders.
    let dashboard: DashboardViewModel
    let categories: CategoriesViewModel
    let digest: DigestViewModel
    let forecast: ForecastViewModel
    let smartAlerts: SmartAlertsViewModel
    // Subscriptions + Recurrings surfaces — previously rendered
    // ComingSoonView placeholders; now backed by real detectors
    // running off the same transaction feed the Forecast surface
    // consumes.
    let subscriptions: SubscriptionsViewModel
    let recurrings: RecurringsViewModel

    /// Memberships store — drives the `.memberships` destination.
    /// Owns the detected `[Membership]` set + optimisation summary.
    let memberships: MembershipsStore

    /// Goals store — drives the .goals destination + the weekly
    /// check-in toast overlay attached to the shell root.
    let goals: GoalsStore

    /// Surfaced when DEBUG/demo mode is on so the user knows the
    /// figures are fixtures rather than live data.
    var showsDemoDataFooter: Bool = false

    /// Dismiss a proactive-feed signal. Wired by the shell to
    /// `AppCore.dismissSignal` so the dismissal persists to the store.
    var onProactiveDismiss: (ProactiveSignal) -> Void = { _ in }

    var body: some View {
        let chrome = CopilotTokens.shell

        HStack(spacing: 0) {
            CopilotSidebar(
                routing: routing,
                chrome: chrome,
                showsDemoFooter: showsDemoDataFooter,
                // Live unreviewed count from the Dashboard VM —
                // mirrors agent 2's `entries.filter { !$0.reviewed }`
                // path; the badge clears once the queue is empty.
                unreviewedCount: dashboard.entries.filter { !$0.reviewed }.count,
                accounts: accounts
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
                dashboard: dashboard,
                categories: categories,
                digest: digest,
                forecast: forecast,
                smartAlerts: smartAlerts,
                subscriptions: subscriptions,
                recurrings: recurrings,
                memberships: memberships,
                goals: goals,
                chrome: chrome,
                showsDemoFooter: showsDemoDataFooter,
                onProactiveDismiss: onProactiveDismiss
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(chrome.contentBackground.color)
        }
        .overlay(alignment: .bottomTrailing) {
            // Weekly check-in toast surfaces whenever the evaluator
            // has unseen results queued. Tapping OPEN routes to the
            // Goals surface; the X dismisses without navigating.
            GoalsToastView(store: goals) {
                routing.select(.goals)
            }
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
    /// Live unreviewed-transactions count surfaced as the Dashboard
    /// row's badge. Drives the Copilot-style "you have N to review"
    /// affordance; `0` hides the badge.
    var unreviewedCount: Int = 0
    /// Live `[FinanceAccount]` source used by the MY ACCOUNTS section.
    /// Passed through from the shell so the sidebar block reflects the
    /// same VM the Accounts detail surface reads off.
    let accounts: FinanceAccountsViewModel

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
                    intelligenceSection
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
    fileprivate static var topLevelRows: [RowSpec] {
        var rows: [RowSpec] = [
            .init(destination: .dashboard,    label: "Dashboard",    icon: "rectangle.grid.2x2"),
            .init(destination: .transactions, label: "Transactions", icon: "arrow.left.arrow.right"),
            .init(destination: .goals,        label: "Goals",        icon: "target")
        ]
        #if DEBUG
        // Cash flow is in-progress: its surface still renders sample
        // figures, so the sidebar row exists only in DEBUG and is never
        // visible to a reviewer or shipping user. The `.cashFlow`
        // destination stays routable via deep link for the same DEBUG
        // builds; release builds simply have no entry point to it.
        rows.append(.init(destination: .cashFlow, label: "Cash flow", icon: "waveform.path.ecg"))
        #endif
        rows.append(contentsOf: [
            .init(destination: .accounts,     label: "Accounts",     icon: "building.columns"),
            .init(destination: .investments,  label: "Investments",  icon: "chart.pie"),
            .init(destination: .categories,   label: "Categories",   icon: "square.grid.3x3"),
            .init(destination: .recurrings,   label: "Recurrings",   icon: "arrow.triangle.2.circlepath"),
            .init(destination: .memberships, label: "Memberships", icon: "square.stack.3d.up.fill"),
            .init(destination: .life,         label: "Life",         icon: "terminal"),
            .init(destination: .advisors,     label: "Advisors",     icon: "person.bubble")
        ])
        return rows
    }

    fileprivate struct RowSpec {
        let destination: RootDestination
        let label: String
        let icon: String
    }

    /// Badge value for a destination. The Dashboard row paints a
    /// Copilot-style "you have N to review" badge sourced from the live
    /// `DashboardViewModel`; everything else returns `nil` so its row
    /// stays clean.
    private func badge(for destination: RootDestination) -> Int? {
        switch destination {
        case .dashboard:
            return unreviewedCount > 0 ? unreviewedCount : nil
        default:
            return nil
        }
    }

    // MARK: MY ACCOUNTS

    private var myAccountsSection: some View {
        CopilotSidebarAccounts(
            accounts: accounts,
            routing: routing,
            chrome: chrome
        )
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

    // MARK: INTELLIGENCE

    /// AI++ wedge surfaces (Digest / Forecast / Smart alerts) painted
    /// as a third sidebar section below MY ACCOUNTS. Mirrors the
    /// Copilot "this column lives below your accounts" layout.
    /// Added 2026-05-17 during the four-branch integration.
    private var intelligenceSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("INTELLIGENCE")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.9)
                .foregroundStyle(chrome.foregroundSecondary.color)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)

            ForEach(CopilotSidebar.intelligenceRows, id: \.destination) { row in
                CopilotNavRow(
                    label: row.label,
                    systemImage: row.icon,
                    badge: nil,
                    isActive: routing.isActive(row.destination),
                    chrome: chrome
                ) {
                    routing.select(row.destination)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    /// Compile-time row metadata for the INTELLIGENCE section.
    /// Mirrors `RootDestination.intelligenceOrder` — the test suite
    /// locks that contract.
    fileprivate static let intelligenceRows: [RowSpec] = [
        .init(destination: .digest,      label: "Digest",       icon: "newspaper"),
        .init(destination: .forecast,    label: "Forecast",     icon: "chart.line.uptrend.xyaxis"),
        .init(destination: .smartAlerts, label: "Smart alerts", icon: "bell.badge")
    ]

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

            Text("v\(Bundle.main.copilotShortVersion) · Synapse")
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

    // Sidebar placeholder rows shown while demo mode is on. Names are
    // intentionally generic ("Sample Credit Card 1", etc.) so the
    // sidebar never reads as a real user's institution list — those
    // appear only after the live FinanceAccountsViewModel migration
    // wires real-account rows in.
    fileprivate static let mockCreditCards: [MockAccount] = [
        .init(id: "demo-credit-1", label: "Sample Credit Card",        balance: "$1,053", swatch: .orange),
        .init(id: "demo-credit-2", label: "Sample Wallet Credit",      balance: nil,      swatch: .blue),
        .init(id: "demo-credit-3", label: "Sample Travel Visa",        balance: nil,      swatch: .gray)
    ]

    fileprivate static let mockDepositories: [MockAccount] = [
        .init(id: "demo-bank-1",   label: "Sample Checking",   balance: "$1,576", swatch: .red),
        .init(id: "demo-bank-2",   label: "Sample Wallet",     balance: nil,      swatch: .blue),
        .init(id: "demo-bank-3",   label: "Sample Savings",    balance: nil,      swatch: .red)
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
                // Left-edge accent bar — 2.5pt wide on active rows.
                // Painted with the brand accent + a subtle bloom so
                // the active row reads as a live indicator rather than
                // a flat marker.
                Rectangle()
                    .fill(isActive ? chrome.brandAccent.color : Color.clear)
                    .frame(width: 2.5)
                    .shadow(
                        color: isActive
                            ? chrome.brandAccent.color.opacity(0.55)
                            : .clear,
                        radius: 4
                    )

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(
                        isActive
                            ? chrome.brandAccent.color
                            : (hover
                                ? chrome.foregroundPrimary.color
                                : chrome.foregroundSecondary.color)
                    )

                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .default))
                    .foregroundStyle(
                        isActive || hover
                            ? chrome.foregroundPrimary.color
                            : chrome.foregroundSecondary.color
                    )

                Spacer()

                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(
                            isActive
                                ? chrome.brandAccent.color
                                : chrome.badgeForeground.color
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isActive
                                    ? chrome.brandAccent.color.opacity(0.15)
                                    : chrome.badgeFill.color)
                        )
                        .accessibilityIdentifier("copilot.sidebar.badge.\(label)")
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackgroundFill)
            )
            .overlay(
                // Hairline border on active row + a subtle warm bleed.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isActive
                            ? chrome.brandAccent.color.opacity(0.18)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .animation(DS.Motion.snappy, value: isActive)
            .animation(DS.Motion.snappy, value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0; cursor($0) }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : [.isButton])
    }

    /// Backgound fill responds to active + hover. Active stacks a
    /// luminance lift on top of a faint amber wash so the row reads
    /// as "the destination you're on" without overwhelming the
    /// other rows.
    private var rowBackgroundFill: some ShapeStyle {
        let amber = chrome.brandAccent.color
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        chrome.activeRowBackground.color,
                        chrome.activeRowBackground.color.opacity(0.85)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        if hover {
            return AnyShapeStyle(amber.opacity(0.06))
        }
        return AnyShapeStyle(Color.clear)
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
/// the system Settings scene (declared in `SynapseMacApp`) opens in
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
    let dashboard: DashboardViewModel
    let categories: CategoriesViewModel
    let digest: DigestViewModel
    let forecast: ForecastViewModel
    let smartAlerts: SmartAlertsViewModel
    let subscriptions: SubscriptionsViewModel
    let recurrings: RecurringsViewModel
    let memberships: MembershipsStore
    let goals: GoalsStore
    let chrome: CopilotTokens.Shell
    let showsDemoFooter: Bool
    var onProactiveDismiss: (ProactiveSignal) -> Void = { _ in }

    /// Hero-card tap target for Cash flow. The cash-flow surface is an
    /// in-progress placeholder, so in release builds it has no entry
    /// point and the card renders non-interactive (`nil`). DEBUG builds
    /// route to the placeholder for local exercise.
    private var cashFlowHeroTap: (() -> Void)? {
        #if DEBUG
        return { routing.select(.cashFlow) }
        #else
        return nil
        #endif
    }

    var body: some View {
        Group {
            switch routing.selection {
            // Live surfaces.
            case .transactions, .finance(.transactions):
                FinanceTransactionsRedesigned(viewModel: transactions, goals: goals)
                    .identity(.cockpitInstrument)
                    .id("transactions")

            case .accounts, .finance(.accounts):
                FinanceAccountsRedesigned(
                    viewModel: accounts,
                    onSelectAccount: { account in
                        routing.select(accountDetail: account.id)
                    }
                )
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

            // Dashboard (agent 2). The default destination; renders
            // the un-reviewed transactions inbox with the inspector
            // on the right.
            case .dashboard:
                DashboardView(
                    viewModel: dashboard,
                    // The Net-this-week hero card links to Cash flow only
                    // in DEBUG; in release the placeholder surface has no
                    // entry point, so the card renders non-interactive.
                    openCashFlow: cashFlowHeroTap,
                    openGoals: { routing.select(.goals) },
                    isDemoData: showsDemoFooter,
                    goalsStore: goals,
                    membershipsStore: memberships,
                    openMemberships: { routing.select(.memberships) },
                    openProactiveSignal: { signal in
                        switch signal.kind {
                        case .upcomingBill, .newRecurring:
                            routing.select(.recurrings)
                        case .anomalousSpend:
                            routing.select(.transactions)
                        }
                    },
                    dismissProactiveSignal: { onProactiveDismiss($0) }
                )
                .identity(.cockpitInstrument)
                .id("dashboard")

            // Categories (agent 3). Pill system + auto-categorize
            // rules + new-category sheet. The shared VM lives on
            // AppCore and has its transactions already projected by
            // bootstrap so the pill rows are populated on first
            // click.
            case .categories:
                CategoriesView(viewModel: categories)
                    .identity(.cockpitInstrument)
                    .id("categories")

            // INTELLIGENCE section — redesigned 2026-05-18.
            case .digest:
                DigestRedesigned(viewModel: digest)
                    .identity(.cockpitInstrument)
                    .id("digest")

            case .forecast:
                ForecastRedesigned(viewModel: forecast)
                    .identity(.cockpitInstrument)
                    .id("forecast")

            case .smartAlerts:
                SmartAlertsRedesigned(viewModel: smartAlerts)
                    .identity(.cockpitInstrument)
                    .id("smartAlerts")

            // Sheet-presented surfaces — selecting them via deep
            // link sets the destination, but the detail pane keeps
            // showing the previous content while the host paints
            // the sheet overlay. Render the placeholder so SwiftUI
            // doesn't fall into the dead branch.
            case .ask:
                CopilotPlaceholder(
                    title: "Ask",
                    subtitle: "Use ⌘K to open the Ask sheet.",
                    chrome: chrome
                ).id("ask")

            case .anomalyExplainer:
                CopilotPlaceholder(
                    title: "Anomaly explainer",
                    subtitle: "Open an anomaly card and tap Why? to see the explanation.",
                    chrome: chrome
                ).id("anomalyExplainer")

            // Four destinations the user stopped agent 4 from
            // building. We paint a shared `ComingSoonView` so the
            // sidebar rows stay clickable and don't crash. Copy
            // matches the brief verbatim (subtitle was renamed from
            // `message:` to honour the existing `ComingSoonView`
            // signature).
            case .goals:
                GoalsView(store: goals) {
                    routing.select(.transactions)
                }
                .identity(.cockpitInstrument)
                .id("goals")

            case .cashFlow:
                CashFlowPlaceholderView()
                    .identity(.cockpitInstrument)
                    .id("cashFlow")

            case .recurrings:
                RecurringsRedesigned(viewModel: recurrings)
                    .identity(.cockpitInstrument)
                    .id("recurrings")

            case .memberships:
                MembershipsView(store: memberships)
                    .identity(.cockpitInstrument)
                    .id("memberships")

            // MY ACCOUNTS drill-down. The sidebar still routes account
            // taps through the id-only `select(account:)` slot (the
            // sidebar uses mock account ids that don't resolve against
            // the live `FinanceAccountsViewModel`). This branch handles
            // `.accountDetail(id:)` set via the new
            // `select(accountDetail:)` setter — exercised by tests and
            // the eventual live-sidebar migration. AccountDetailHost
            // owns the VM in @State so range-chip taps survive.
            case .accountDetail(let id):
                AccountDetailRedesignedHost(
                    id: id,
                    accounts: accounts.accounts,
                    allTransactions: transactions.rows,
                    onClose: { routing.select(.accounts) }
                )
                .identity(.cockpitInstrument)
                .id("accountDetail.\(id)")
            }
        }
        // Detail-pane route transition. Each destination uses its own
        // `.id(...)` so SwiftUI rebuilds when the selection changes;
        // we crossfade with a slight upward slide so the new surface
        // arrives instead of snapping.
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 6)),
                removal: .opacity
            )
        )
        .animation(DS.Motion.smooth, value: routing.selection)
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

// MARK: - AccountDetailRedesignedHost
//
// Lifecycle wrapper that builds an AccountDetailViewModel from a
// captured account id + transactions slice, then renders the
// redesigned per-account drill-down. Mirrors the pattern of the
// legacy AccountDetailHost in Features/AccountDetail/AccountDetailView.swift
// but targets AccountDetailRedesigned (which owns the new 64pt hero,
// AI insights, transactions feed, and sync status card).

@MainActor
private struct AccountDetailRedesignedHost: View {
    let id: String
    let accounts: [FinanceAccount]
    let allTransactions: [Models.Transaction]
    let onClose: () -> Void

    @State private var viewModel: AccountDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                AccountDetailRedesigned(viewModel: vm, onClose: onClose)
            } else {
                AccountDetailRedesignedEmpty(onClose: onClose)
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
