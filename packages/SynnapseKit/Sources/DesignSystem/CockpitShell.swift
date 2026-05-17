import SwiftUI
import Foundation

/// Cockpit Dense shell — the app-wide chrome.
///
/// The shell is the frame an unidentified subtree inherits. Inside, each
/// surviving surface still applies its own identity:
///   - LIFE applies `.identity(.terminalAmber)`
///   - Advisors / Settings apply `.identity(.editorial)`
///   - Finance keeps `.identity(.cockpitInstrument)` — the inner identity
///     happens to match the shell, which is intentional. Finance is what
///     gave the shell its visual vocabulary in the first place.
///
/// The renderer here paints the deterministic preview state used by the
/// snapshot suite. Real apps wrap it with live navigation in
/// `apps/Shared/RootView.swift`.
@MainActor
public struct CockpitShellPreview: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// When true, paints a single-line "demo data" footer in the sidebar
    /// so the operator can tell at a glance the figures aren't real.
    /// Set by the DEBUG shells (which wire the Mock APIs); release
    /// builds default to `false` and the line disappears entirely so
    /// the snapshot suite remains pixel-stable.
    private let showsDemoDataFooter: Bool

    public init(showsDemoDataFooter: Bool = false) {
        self.showsDemoDataFooter = showsDemoDataFooter
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)

        #if os(macOS)
        macLayout(tokens: tokens)
        #else
        iosLayout(tokens: tokens)
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func macLayout(tokens: TokenSet) -> some View {
        HStack(spacing: 0) {
            CockpitSidebar(tokens: tokens, showsDemoFooter: showsDemoDataFooter)
                .frame(width: 220)
                .background(tokens.surface.color)

            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.18))
                .frame(width: 1)

            CockpitContent(tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tokens.background.color)
        }
        .font(Tokens.tickerFont().swiftUIFont)
        .foregroundStyle(tokens.foregroundPrimary.color)
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private func iosLayout(tokens: TokenSet) -> some View {
        VStack(spacing: 0) {
            CockpitContent(tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tokens.background.color)

            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.18))
                .frame(height: 1)

            // Mini sidebar overview kept visible on phone width so the
            // snapshot diff against the macOS rendering is meaningful
            // (same sections, vertically stacked).
            CockpitSidebar(tokens: tokens, showsDemoFooter: showsDemoDataFooter)
                .frame(height: 240)
                .background(tokens.surface.color)
        }
        .font(Tokens.tickerFont().swiftUIFont)
        .foregroundStyle(tokens.foregroundPrimary.color)
    }
    #endif
}

// MARK: - Sidebar (sections + tree-style disclosure)

@MainActor
private struct CockpitSidebar: View {
    let tokens: TokenSet
    var showsDemoFooter: Bool = false

    private struct Row: Identifiable {
        let id: String
        let label: String
        let depth: Int
    }

    /// Sidebar tree, encoded as a flat list with a `depth` column so the
    /// snapshot is deterministic (no NavigationSplitView host context
    /// games). Scope: private-life surfaces only — work-flavoured
    /// sections (Spotlight, Approvals, People, Inbox, Sequences,
    /// Octagon) live in the synapse-v2 web app, not this client.
    ///
    ///   FINANCE
    ///     Personal
    ///     Accounts
    ///     Investments
    ///   LIFE
    ///   ADVISORS
    private static let rows: [Row] = [
        .init(id: "finance",      label: "FINANCE",   depth: 0),
        .init(id: "finance-pers", label: "Personal",     depth: 1),
        .init(id: "finance-acc",  label: "Accounts",     depth: 1),
        .init(id: "finance-inv",  label: "Investments",  depth: 1),
        .init(id: "life",       label: "LIFE",      depth: 0),
        .init(id: "advisors",   label: "ADVISORS",  depth: 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(tokens.accent.color)
                    .frame(width: 8, height: 8)
                Text("SYNAPSE")
                    .font(Tokens.headerFont(size: 12).swiftUIFont)
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Self.rows) { row in
                HStack(spacing: 4) {
                    if row.depth == 0 {
                        Text("\u{25B8}") // ▸ tree caret for sections
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    } else {
                        Text("  ")
                    }
                    Text(row.label)
                        .font(Tokens.tickerFont(
                            size: row.depth == 0 ? 11 : 10,
                            weight: row.depth == 0 ? .semibold : .regular
                        ).swiftUIFont)
                        .foregroundStyle(
                            row.depth == 0
                                ? tokens.foregroundPrimary.color
                                : tokens.foregroundSecondary.color
                        )
                    Spacer()
                }
                .padding(.leading, CGFloat(8 + row.depth * 12))
                .padding(.trailing, 8)
                .padding(.vertical, 3)
            }

            Spacer(minLength: 0)

            if showsDemoFooter {
                // Subtle monospace footer — the cockpit picks its own
                // identity, so we paint inside the same accent palette
                // rather than introducing a new color.
                Text("demo data \u{00B7} sign in to sync")
                    .font(Tokens.tickerFont(size: 9).swiftUIFont)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("cockpit.sidebar.demoDataFooter")
            }
        }
    }
}

// MARK: - Content area (ledger stripe + signed deltas)

@MainActor
private struct CockpitContent: View {
    let tokens: TokenSet

    /// `CFBundleShortVersionString` from the hosting app's Info.plist.
    /// Falls back to "0.0.0" when the package is exercised outside an app
    /// bundle (snapshot tests, swift-test runner) so the shell stays
    /// deterministic for the snapshot suite while still showing the real
    /// marketing version inside the live app.
    static var appShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    /// Deterministic preview rows. The shell snapshot doesn't depend on
    /// any live VM — it just demonstrates the ledger stripe + signed
    /// deltas the shell guarantees.
    fileprivate struct Row: Identifiable {
        let id: Int
        let symbol: String
        let label: String
        let value: String
        let delta: Double
    }

    fileprivate static let rows: [Row] = [
        .init(id: 0, symbol: "AAPL",  label: "Apple Inc.",         value: " 187.34", delta:  0.42),
        .init(id: 1, symbol: "MSFT",  label: "Microsoft",          value: " 402.21", delta:  1.18),
        .init(id: 2, symbol: "NVDA",  label: "NVIDIA",             value: " 921.05", delta: -0.66),
        .init(id: 3, symbol: "GOOG",  label: "Alphabet",           value: " 142.18", delta:  0.04),
        .init(id: 4, symbol: "META",  label: "Meta Platforms",     value: " 478.99", delta: -1.31),
        .init(id: 5, symbol: "BRK.B", label: "Berkshire Hathaway", value: " 405.62", delta:  0.18),
        .init(id: 6, symbol: "AMZN",  label: "Amazon",             value: " 178.55", delta:  0.71),
        .init(id: 7, symbol: "JPM",   label: "JPMorgan Chase",     value: " 201.47", delta: -0.22)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                Text("LEDGER")
                    .font(Tokens.headerFont(size: 14).swiftUIFont)
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Spacer()
                Text("v\(Self.appShortVersion)  ·  Cockpit Dense")
                    .font(Tokens.tickerFont(size: 10).swiftUIFont)
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle()
                .fill(tokens.foregroundSecondary.color.opacity(0.18))
                .frame(height: 1)

            ForEach(Array(Self.rows.enumerated()), id: \.element.id) { idx, row in
                LedgerRow(row: row, tokens: tokens, striped: idx.isMultiple(of: 2))
            }

            Spacer(minLength: 0)
        }
    }
}

@MainActor
private struct LedgerRow: View {
    let row: CockpitContent.Row
    let tokens: TokenSet
    let striped: Bool

    private var deltaSign: String {
        if row.delta > 0 { return "+" }
        if row.delta < 0 { return "" } // negative numbers carry their own sign
        return " "
    }

    private var deltaColor: Color {
        if row.delta > 0 { return tokens.gainAccent.color }
        if row.delta < 0 { return tokens.lossAccent.color }
        return tokens.foregroundSecondary.color
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(row.symbol)
                .font(Tokens.tickerFont(weight: .semibold).swiftUIFont)
                .frame(width: 64, alignment: .leading)
            Text(row.label)
                .font(Tokens.tickerFont().swiftUIFont)
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(1)
            Spacer()
            Text(row.value)
                .font(Tokens.tickerFont().swiftUIFont)
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(String(format: "%@%.2f%%", deltaSign, row.delta))
                .font(Tokens.tickerFont(weight: .semibold).swiftUIFont)
                .foregroundStyle(deltaColor)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(striped ? tokens.ledgerStripe.color : tokens.background.color)
    }
}
