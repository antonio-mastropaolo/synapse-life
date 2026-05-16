import SwiftUI
import Models
import DesignSystem

/// Octagon hub. Two visual idioms over the same `OctagonViewModel`:
///
///   - **macOS**: a `NavigationSplitView` with a memberships list as the
///     content column and a trailing `inspector` pane that surfaces the
///     vendor intel brief. Selecting a row fires `viewModel.select(vendor:)`.
///   - **iOS**: a vertical list of memberships, plus a `SwipeDeck`
///     `TabView(.page)` of the same cards along the top. Selecting a row
///     opens a bottom-sheet inspector via `.sheet(item:)` with detents
///     `[.medium, .large]`.
///
/// Identity: CockpitInstrument — same family as the Finance hub.
@MainActor
public struct OctagonView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: OctagonViewModel

    public init(viewModel: OctagonViewModel) {
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
        NavigationSplitView {
            membershipsList
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 480)
        } detail: {
            OctagonInspector(state: viewModel.inspector)
        }
        .navigationTitle("Octagon")
    }

    private var membershipsList: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack {
            tokens.background.color
            switch viewModel.state {
            case .idle, .loading:
                ProgressView().tint(tokens.foregroundSecondary.color)
            case .error(let msg):
                errorBody(message: msg)
            case .empty:
                emptyBody
            case .ready(let cards):
                List(selection: Binding<String?>(
                    get: { viewModel.selectedVendor },
                    set: { viewModel.select(vendor: $0) }
                )) {
                    Section {
                        ForEach(cards) { card in
                            MembershipRow(card: card)
                                .tag(card.vendor)
                                .listRowBackground(tokens.surface.color)
                        }
                    } header: {
                        Text("Memberships")
                            .font(tokens.tickerFont(size: 10, weight: .semibold))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(tokens.background.color)
            }
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return NavigationStack {
            ZStack(alignment: .top) {
                tokens.background.color.ignoresSafeArea()
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView().tint(tokens.foregroundSecondary.color)
                case .error(let msg):
                    errorBody(message: msg)
                case .empty:
                    emptyBody
                case .ready(let cards):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            swipeDeck(cards: cards)
                                .frame(height: 140)
                                .padding(.horizontal, 16)
                            Text("All memberships")
                                .font(tokens.tickerFont(size: 10, weight: .semibold))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                                .padding(.horizontal, 16)
                            ForEach(cards) { card in
                                MembershipRow(card: card)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(tokens.surface.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.horizontal, 16)
                                    .onTapGesture {
                                        viewModel.select(vendor: card.vendor)
                                    }
                            }
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationTitle("Octagon")
            .sheet(item: inspectorBinding) { vendor in
                NavigationStack {
                    OctagonInspector(state: viewModel.inspector)
                        .navigationTitle(vendor.value)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var inspectorBinding: Binding<VendorIdentifier?> {
        Binding(
            get: {
                guard let v = viewModel.selectedVendor else { return nil }
                return VendorIdentifier(value: v)
            },
            set: { newValue in
                viewModel.select(vendor: newValue?.value)
            }
        )
    }

    @ViewBuilder
    private func swipeDeck(cards: [MembershipCard]) -> some View {
        let top = Array(cards.prefix(8))
        TabView {
            ForEach(top) { card in
                SwipeDeckCard(card: card) {
                    viewModel.select(vendor: card.vendor)
                }
                .padding(.bottom, 24)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }
    #endif

    // MARK: - Common

    private var emptyBody: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 6) {
            Text("No memberships detected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("We'll surface them as transactions land.")
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.vertical, 40)
    }

    private func errorBody(message: String) -> some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 6) {
            Text("Couldn't load memberships")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(message)
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding()
    }
}

// MARK: - Identifier wrapper for iOS sheet(item:)

#if os(iOS)
struct VendorIdentifier: Identifiable, Hashable {
    var id: String { value }
    let value: String
}
#endif

// MARK: - Membership row

struct MembershipRow: View {
    let card: MembershipCard
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 12) {
            Text(initials(for: card.vendor))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .frame(width: 32, height: 32)
                .background(tokens.surface.color)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(card.vendor)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("\(card.cadence.shortLabel) · " + statusLabel)
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMoney(card.averageAmount))
                    .font(tokens.tickerFont(size: 12, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("≈ \(formatMoney(card.monthlyEquivalent))/mo")
                    .font(tokens.tickerFont(size: 9))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    private var statusLabel: String {
        switch card.status {
        case .active: return "active"
        case .canceled: return "canceled"
        case .paused: return "paused"
        case .unknown: return "—"
        }
    }

    private func initials(for vendor: String) -> String {
        let parts = vendor.split(separator: " ", omittingEmptySubsequences: true)
        if let first = parts.first?.first, let last = parts.dropFirst().first?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(vendor.prefix(2)).uppercased()
    }

    private func formatMoney(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD"))
    }
}

// MARK: - Swipe deck card (iOS)

struct SwipeDeckCard: View {
    let card: MembershipCard
    let onTap: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.vendor)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                HStack {
                    Text(card.cadence.shortLabel)
                        .font(tokens.tickerFont(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.accent.color)
                    Spacer()
                    Text(card.averageAmount.formatted(.currency(code: "USD")))
                        .font(tokens.tickerFont(size: 14, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                }
                Spacer()
                Text("≈ \(card.monthlyEquivalent.formatted(.currency(code: "USD")))/mo")
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inspector

struct OctagonInspector: View {
    let state: OctagonViewModel.InspectorState
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        ZStack {
            tokens.background.color
            switch state {
            case .closed:
                placeholder
            case .loading(let vendor):
                VStack(spacing: 8) {
                    ProgressView().tint(tokens.foregroundSecondary.color)
                    Text("Querying Octagon for \(vendor)")
                        .font(tokens.tickerFont(size: 10))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            case .ready(let brief):
                briefBody(brief: brief)
            case .error(let vendor, let message):
                VStack(spacing: 6) {
                    Text("No intel for \(vendor)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(message)
                        .font(tokens.tickerFont(size: 10))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }

    private var placeholder: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 6) {
            Text("Vendor intel")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Select a membership to load the Octagon brief.")
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func briefBody(brief: OctagonVendor) -> some View {
        let tokens = theme.tokens(for: scheme)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(brief.legalName ?? brief.vendor)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(brief.primaryIndustry ?? "—")
                        .font(tokens.tickerFont(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Divider().overlay(tokens.foregroundSecondary.color.opacity(0.2))
                LabeledRow(label: "Status", value: brief.status?.capitalized ?? "—")
                LabeledRow(label: "HQ", value: brief.headquartersDisplay)
                LabeledRow(label: "Founded", value: brief.yearFounded.map { "\($0)" } ?? "—")
                LabeledRow(label: "Employees", value: brief.employees.map { "\($0)" } ?? "—")
                LabeledRow(label: "Last valuation", value: formatUsdMillions(brief.lastValuationUsdM))
                LabeledRow(label: "Revenue", value: formatUsdMillions(brief.revenueUsdM))
                LabeledRow(label: "VC raised", value: formatUsdMillions(brief.vcRaisedUsdM))
                if !brief.competitors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Competitors")
                            .font(tokens.tickerFont(size: 10, weight: .semibold))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                        Text(brief.competitors.joined(separator: ", "))
                            .font(tokens.tickerFont(size: 11))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                    }
                }
                if let ceo = brief.ceo.name {
                    LabeledRow(label: "CEO", value: ceo)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatUsdMillions(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let asDouble = NSDecimalNumber(decimal: value).doubleValue
        if asDouble >= 1_000 {
            return String(format: "$%.1fB", asDouble / 1_000.0)
        }
        if asDouble >= 1 {
            return String(format: "$%.0fM", asDouble)
        }
        return String(format: "$%.0fK", asDouble * 1_000.0)
    }
}

private struct LabeledRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String
    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack {
            Text(label)
                .font(tokens.tickerFont(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            Text(value)
                .font(tokens.tickerFont(size: 12))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }
}
