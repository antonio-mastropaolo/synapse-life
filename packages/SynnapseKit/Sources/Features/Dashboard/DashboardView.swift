import SwiftUI
import DesignSystem
import Models

/// Top-level Dashboard surface — the inbox of un-reviewed transactions
/// with the v2 hero row, animated review queue, and the inspector
/// (Goals + Spending pulse + Anomaly + AI).
///
/// macOS: VStack { header, HeroRow, list, ActionRibbon } | Inspector.
/// iOS:   VStack { header, HeroRow (h-scroll), list (List),
///                 ActionRibbon } with the inspector cards collapsed
///        below the list (single-column).
///
/// The view is intentionally thin — every reducer call sits on
/// [[DashboardViewModel]] / [[DashboardWidgetReducer]] so the SwiftUI
/// body never re-derives state per render.
@MainActor
public struct DashboardView: View {

    @Bindable private var viewModel: DashboardViewModel

    // MARK: - Closure dependencies wired by the integrator.

    private var iconResolver: ((String) -> Image?)?
    private var openCashFlow: (() -> Void)?
    private var openGoals: (() -> Void)?
    private var openTopCategory: (() -> Void)?
    private var openNextBill: (() -> Void)?
    private var openAnomalyExplainer: ((String) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        viewModel: DashboardViewModel,
        iconResolver: ((String) -> Image?)? = nil,
        openCashFlow: (() -> Void)? = nil,
        openGoals: (() -> Void)? = nil,
        openTopCategory: (() -> Void)? = nil,
        openNextBill: (() -> Void)? = nil,
        openAnomalyExplainer: ((String) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.iconResolver = iconResolver
        self.openCashFlow = openCashFlow
        self.openGoals = openGoals
        self.openTopCategory = openTopCategory
        self.openNextBill = openNextBill
        self.openAnomalyExplainer = openAnomalyExplainer
    }

    public var body: some View {
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
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(tokens: tokens)
                DashboardHeroRow(
                    widgetState: viewModel.widgetState,
                    currency: defaultCurrency,
                    openCashFlow: openCashFlow,
                    openTopCategory: openTopCategory,
                    openNextBill: openNextBill,
                    iconResolver: iconResolver
                )
                Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
                listScrollMac(tokens: tokens)
                Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
                DashboardActionRibbon(
                    footerText: viewModel.footerCountText,
                    selectionCount: viewModel.selectionCount,
                    markSelected: { _ = viewModel.markSelectedAsReviewed() },
                    markAll: { _ = viewModel.markAll() },
                    skipAll: { viewModel.skipAll() }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.background.color)

            DashboardInspectorView(
                widgetState: viewModel.widgetState,
                goalsCurrency: defaultCurrency,
                openGoals: openGoals,
                openAnomalyExplainer: openAnomalyExplainer
            )
            .frame(width: 280)
            .background(tokens.background.color)
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 0) {
            header(tokens: tokens)
            ScrollView(.horizontal, showsIndicators: false) {
                DashboardHeroRow(
                    widgetState: viewModel.widgetState,
                    currency: defaultCurrency,
                    openCashFlow: openCashFlow,
                    openTopCategory: openTopCategory,
                    openNextBill: openNextBill,
                    iconResolver: iconResolver
                )
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
            listScrollIOS(tokens: tokens)
            Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
            DashboardActionRibbon(
                footerText: viewModel.footerCountText,
                selectionCount: viewModel.selectionCount,
                markSelected: { _ = viewModel.markSelectedAsReviewed() },
                markAll: { _ = viewModel.markAll() },
                skipAll: { viewModel.skipAll() }
            )
        }
        .background(tokens.background.color)
    }
    #endif

    // MARK: - Header

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Dashboard")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - List (macOS — LazyVStack with drag + transitions)

    #if os(macOS)
    @ViewBuilder
    private func listScrollMac(tokens: TokenSet) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if viewModel.sections.isEmpty {
                    emptyState(tokens: tokens)
                } else {
                    ForEach(viewModel.sections) { section in
                        sectionHeader(section: section, tokens: tokens)
                        ForEach(section.entries) { entry in
                            expandableRow(entry: entry, tokens: tokens)
                                .draggable(entry.id)
                                .transition(
                                    reduceMotion
                                    ? .opacity
                                    : .move(edge: .trailing).combined(with: .opacity)
                                )
                            Divider()
                                .background(tokens.foregroundSecondary.color.opacity(0.10))
                                .padding(.leading, 14)
                        }
                    }
                }
            }
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.32),
                value: viewModel.entries.map(\.reviewed)
            )
        }
    }
    #endif

    // MARK: - List (iOS — List with swipe actions)

    #if os(iOS)
    @ViewBuilder
    private func listScrollIOS(tokens: TokenSet) -> some View {
        if viewModel.sections.isEmpty {
            ScrollView { emptyState(tokens: tokens) }
        } else {
            List {
                ForEach(viewModel.sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            expandableRow(entry: entry, tokens: tokens)
                                .listRowBackground(tokens.background.color)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        viewModel.toggleSelection(entry.id)
                                        _ = viewModel.markSelectedAsReviewed()
                                    } label: {
                                        Label("Review", systemImage: "checkmark")
                                    }
                                    .tint(tokens.accent.color)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        viewModel.toggleSelection(entry.id)
                                    } label: {
                                        Label("Skip", systemImage: "xmark")
                                    }
                                    .tint(tokens.foregroundSecondary.color)
                                }
                            Divider()
                                .background(tokens.foregroundSecondary.color.opacity(0.10))
                                .padding(.leading, 14)
                                .listRowBackground(tokens.background.color)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                        }
                    } header: {
                        sectionHeader(section: section, tokens: tokens)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(tokens.background.color)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(tokens.background.color)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.32),
                value: viewModel.entries.map(\.reviewed)
            )
        }
    }
    #endif

    // MARK: - Row composition

    @ViewBuilder
    private func expandableRow(entry: DashboardEntry, tokens: TokenSet) -> some View {
        DashboardExpandableRow(
            entry: entry,
            isSelected: bindingForSelection(of: entry.id),
            isExpanded: viewModel.expandedRowId == entry.id,
            onToggleExpand: { viewModel.toggleExpanded(entry.id) },
            recentPeers: viewModel.recentSameMerchant(for: entry.id)
        )
    }

    @ViewBuilder
    private func sectionHeader(section: DashboardSection, tokens: TokenSet) -> some View {
        HStack {
            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func emptyState(tokens: TokenSet) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(tokens.gainAccent.color)
            Text("Inbox zero")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Everything's been reviewed.")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Bindings

    /// Returns a binding into the view model's selection set for a
    /// single row id. SwiftUI re-creates this binding every render,
    /// which is intentional — the read closure captures the id, not
    /// the live entry, so a row that scrolls off-screen does not
    /// hold onto stale state.
    private func bindingForSelection(of id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSelected(id) },
            set: { _ in viewModel.toggleSelection(id) }
        )
    }

    // MARK: - Locale

    /// Default currency for the inspector's net figure. Picked from
    /// the first transaction so a USD-only ledger never renders an
    /// EUR-shaped figure; the server-driven case will surface this
    /// as a future setting.
    private var defaultCurrency: String {
        viewModel.entries.first?.transaction.currency ?? "USD"
    }
}

#if DEBUG
@MainActor
public enum DashboardPreviewFactory {

    /// Default upcoming-bills set used by demo + snapshot tests. Three
    /// rows so the NEXT BILL hero card lands on a "tomorrow" urgency.
    public static func demoUpcomingBills(
        relativeTo today: Date = DashboardDemoData.referenceDate,
        calendar: Calendar = DashboardDemoData.calendar
    ) -> [DashboardWidgetReducer.Upcoming] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let three    = calendar.date(byAdding: .day, value: 3, to: today)!
        let five     = calendar.date(byAdding: .day, value: 5, to: today)!
        return [
            DashboardWidgetReducer.Upcoming(
                merchant: "NETFLIX",
                amount: Decimal(string: "22.99")!,
                dueDate: tomorrow
            ),
            DashboardWidgetReducer.Upcoming(
                merchant: "SPOTIFY",
                amount: Decimal(string: "16.99")!,
                dueDate: three
            ),
            DashboardWidgetReducer.Upcoming(
                merchant: "ICLOUD+",
                amount: Decimal(string: "9.99")!,
                dueDate: five
            )
        ]
    }

    /// Default AI narration so the inspector card paints in the demo.
    public static let demoAINarration = DashboardWidgetReducer.AINarration(
        sentence: "You're tracking $42 below typical for a Friday. Restaurants are the biggest cluster this week.",
        cta: "Open Restaurants"
    )

    /// Builds a fully-seeded dashboard with the canonical demo data.
    /// Used by `#Preview` blocks and by snapshot tests that import
    /// the Features module.
    public static func demoViewModel() -> DashboardViewModel {
        DashboardViewModel(
            entries: DashboardDemoData.previewEntries,
            ledgerTotal: DashboardDemoData.ledgerTotal,
            calendar: DashboardDemoData.calendar,
            referenceDate: DashboardDemoData.referenceDate,
            locale: Locale(identifier: "en_US_POSIX"),
            upcomingBillsProvider: { demoUpcomingBills() },
            anomaliesProvider: {
                // Pull two big-amount expense rows out of the demo
                // ledger so the anomaly mini-list paints with real
                // entries (no need to hand-author a separate fixture).
                DashboardDemoData.previewEntries
                    .filter { ($0.transaction.amount ?? 0) < -80 }
                    .prefix(2)
                    .map { $0 }
            },
            aiSuggestionProvider: { demoAINarration }
        )
    }
}
#endif
