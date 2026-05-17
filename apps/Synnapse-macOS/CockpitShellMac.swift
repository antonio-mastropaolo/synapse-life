import SwiftUI
import AppKit
import DesignSystem
import Features
import Networking

/// macOS Cockpit shell — the real, live shell the app boots into.
///
/// Replaces the static `CockpitShellPreview` chrome that was previously
/// painted into the main window. The preview shell stays in DesignSystem
/// for the deterministic snapshot suite; this is what users see.
///
/// Architecture: a flat `HStack` (sidebar + detail). We deliberately do
/// NOT use a top-level `NavigationSplitView` because `FinancePersonalView`
/// is itself a three-column split — nesting would produce a four-column
/// rendering that the brief explicitly does not want. The shell carries
/// the routing state in [[RootShellViewModel]]; each detail surface
/// owns its own internal navigation.
///
/// Identities: the shell inherits the env-default Cockpit Dense identity.
/// Detail surfaces still apply their own identity (Life paints with
/// `.terminalAmber`, Advisors paints with `.cockpitInstrument`).
@MainActor
struct CockpitShellMac: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable var routing: RootShellViewModel

    let personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel
    let lifeAPI: LifeAPI
    let advisors: AdvisorsListViewModel

    /// Surfaced when DEBUG/demo mode is on so the user knows the figures
    /// are fixtures rather than live data.
    var showsDemoDataFooter: Bool = false

    var body: some View {
        let tokens = theme.tokens(for: scheme)

        HStack(spacing: 0) {
            CockpitSidebarMac(
                routing: routing,
                tokens: tokens,
                showsDemoFooter: showsDemoDataFooter
            )
            .frame(width: 228)
            .background(tokens.surface.color)

            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.18))
                .frame(width: 1)

            DetailPane(
                routing: routing,
                personal: personal,
                accounts: accounts,
                transactions: transactions,
                investments: investments,
                lifeAPI: lifeAPI,
                advisors: advisors
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.background.color)
        }
        .foregroundStyle(tokens.foregroundPrimary.color)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sidebar

@MainActor
private struct CockpitSidebarMac: View {

    @Bindable var routing: RootShellViewModel
    let tokens: TokenSet
    var showsDemoFooter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    section(
                        header: "FINANCE",
                        leadingIcon: "chart.line.uptrend.xyaxis",
                        parent: .finance(.personal),
                        isParentActive: routing.isActive(.finance(.personal)),
                        children: childRows
                    )

                    section(
                        header: "LIFE",
                        leadingIcon: "terminal",
                        parent: .life,
                        isParentActive: routing.isActive(.life)
                    )

                    section(
                        header: "ADVISORS",
                        leadingIcon: "person.bubble",
                        parent: .advisors,
                        isParentActive: routing.isActive(.advisors)
                    )
                }
                .padding(.vertical, 18)
            }

            Spacer(minLength: 0)

            footer
        }
    }

    private var childRows: [(label: String, surface: FinanceSurface)] {
        [
            ("Personal",     .personal),
            ("Accounts",     .accounts),
            ("Transactions", .transactions),
            ("Investments",  .investments)
        ]
    }

    private var brandHeader: some View {
        HStack(spacing: 8) {
            // Tiny instrument square — a deliberate echo of the accent in
            // the bottom toolbars. Two squares, slightly offset, give the
            // wordmark a single mark to anchor against.
            ZStack {
                Rectangle()
                    .stroke(tokens.foregroundSecondary.color.opacity(0.55), lineWidth: 1)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(tokens.accent.color)
                    .frame(width: 6, height: 6)
                    .offset(x: 1.5, y: 1.5)
            }

            // The wordmark is the ONE place that breaks the SF Mono rule.
            // SF Pro Display Medium reads as designed, not typed — exactly
            // the contrast point the brief asks for.
            Text("Synapse")
                .font(.system(size: 18, weight: .medium, design: .default))
                .tracking(0.4)
                .foregroundStyle(tokens.foregroundPrimary.color)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func section(
        header: String,
        leadingIcon: String,
        parent: RootDestination,
        isParentActive: Bool,
        children: [(label: String, surface: FinanceSurface)] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section header treatment: SF Mono Semibold 11pt, uppercased,
            // letter-spacing for breath. The header itself is also a
            // button — clicking FINANCE lands on `.personal` by design.
            SidebarRow(
                label: header,
                systemImage: leadingIcon,
                isActive: isParentActive,
                isParent: true,
                tokens: tokens
            ) {
                routing.select(parent)
            }

            ForEach(children, id: \.surface) { child in
                SidebarRow(
                    label: child.label,
                    systemImage: nil,
                    isActive: routing.isActiveFinanceSurface(child.surface),
                    isParent: false,
                    tokens: tokens
                ) {
                    routing.select(.finance(child.surface))
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.18))
                .frame(height: 1)
                .padding(.bottom, 10)

            Text("v\(Bundle.main.shortVersion) · Cockpit Dense")
                .font(Tokens.tickerFont(size: 9).swiftUIFont)
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(1)

            if showsDemoFooter {
                Text("demo data · sign in to sync")
                    .font(Tokens.tickerFont(size: 9).swiftUIFont)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
                    .accessibilityIdentifier("cockpit.sidebar.demoDataFooter")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Sidebar row

@MainActor
private struct SidebarRow: View {
    let label: String
    let systemImage: String?
    let isActive: Bool
    let isParent: Bool
    let tokens: TokenSet
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Left-edge accent bar — 2pt wide, full row height. The
                // bar is what telegraphs "this row is the current
                // destination" without resorting to a heavy background.
                Rectangle()
                    .fill(isActive ? tokens.accent.color : Color.clear)
                    .frame(width: 2)

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(
                            isActive
                                ? tokens.foregroundPrimary.color
                                : tokens.foregroundSecondary.color
                        )
                        .frame(width: 14, alignment: .center)
                } else {
                    // Children sit slightly indented under their parent
                    // icon column so the eye groups them as one.
                    Color.clear.frame(width: 14)
                }

                Text(label)
                    .font(
                        isParent
                            ? .system(size: 11, weight: .semibold, design: .monospaced)
                            : .system(size: 12, weight: .regular, design: .monospaced)
                    )
                    .tracking(isParent ? 1.2 : 0.0)
                    .foregroundStyle(rowForeground)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.leading, isParent ? 0 : 16)
            .padding(.trailing, 12)
            .padding(.vertical, isParent ? 6 : 5)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // SwiftUI's onHover provides the hover state we paint with —
            // we intentionally avoid a custom NSHostingView with a
            // trackingArea here because `.onHover` already routes through
            // AppKit's tracking machinery in SwiftUI on macOS.
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : [.isButton])
    }

    private var rowForeground: Color {
        if isActive {
            return tokens.foregroundPrimary.color
        }
        if isHovering {
            return tokens.foregroundPrimary.color
        }
        if isParent {
            return tokens.foregroundPrimary.color
        }
        return tokens.foregroundSecondary.color
    }

    private var rowBackground: Color {
        if isActive {
            return tokens.foregroundSecondary.color.opacity(0.10)
        }
        if isHovering {
            return tokens.foregroundSecondary.color.opacity(0.05)
        }
        return Color.clear
    }
}

// MARK: - Detail pane

@MainActor
private struct DetailPane: View {

    @Bindable var routing: RootShellViewModel

    let personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel
    let lifeAPI: LifeAPI
    let advisors: AdvisorsListViewModel

    var body: some View {
        Group {
            switch routing.selection {
            case .finance(let surface):
                FinanceDetailPane(
                    surface: surface,
                    personal: personal,
                    accounts: accounts,
                    transactions: transactions,
                    investments: investments,
                    onChange: { routing.select(.finance($0)) }
                )
                .identity(.cockpitInstrument)
                .id("finance.\(surface.rawValue)")
            case .life:
                LifeTerminalScene(api: lifeAPI)
                    .identity(.terminalAmber)
                    .id("life")
            case .advisors:
                AdvisorsView(viewModel: advisors)
                    .identity(.cockpitInstrument)
                    .id("advisors")
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: routing.selection)
    }
}

// MARK: - Finance detail pane

/// Wraps the four Finance surfaces with a thin sub-router so the user can
/// switch between Personal / Accounts / Transactions / Investments without
/// leaving the main window. Mirrors the sidebar selection.
@MainActor
private struct FinanceDetailPane: View {

    let surface: FinanceSurface
    let personal: FinancePersonalViewModel
    let accounts: FinanceAccountsViewModel
    let transactions: FinanceTransactionsViewModel
    let investments: FinanceInvestmentsViewModel
    let onChange: (FinanceSurface) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Sub-router strip. A horizontal segmented control, but
            // rendered as flat tabs so it reads as part of the cockpit
            // rather than as a UIKit-style segmented control.
            FinanceSubRouter(surface: surface, onChange: onChange)

            Divider()
                .opacity(0.4)

            switch surface {
            case .personal:     FinancePersonalView(viewModel: personal)
            case .accounts:     FinanceAccountsView(viewModel: accounts)
            case .transactions: FinanceTransactionsView(viewModel: transactions)
            case .investments:  FinanceInvestmentsView(viewModel: investments)
            }
        }
    }
}

@MainActor
private struct FinanceSubRouter: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let surface: FinanceSurface
    let onChange: (FinanceSurface) -> Void

    var body: some View {
        let tokens = theme.tokens(for: scheme)

        HStack(spacing: 0) {
            ForEach(FinanceSurface.allCases) { candidate in
                Tab(
                    label: candidate.title,
                    systemImage: candidate.systemImage,
                    isActive: candidate == surface,
                    tokens: tokens
                ) {
                    onChange(candidate)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tokens.surface.color.opacity(0.6))
    }

    private struct Tab: View {
        let label: String
        let systemImage: String
        let isActive: Bool
        let tokens: TokenSet
        let action: () -> Void

        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .regular))
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(
                    isActive
                        ? tokens.foregroundPrimary.color
                        : tokens.foregroundSecondary.color
                )
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            isActive
                                ? tokens.foregroundSecondary.color.opacity(0.12)
                                : (hover ? tokens.foregroundSecondary.color.opacity(0.05) : Color.clear)
                        )
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? tokens.accent.color : Color.clear)
                        .frame(height: 1.5)
                        .offset(y: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in
                hover = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

// MARK: - Bundle helper

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
