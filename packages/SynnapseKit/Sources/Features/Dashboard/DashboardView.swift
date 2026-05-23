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
    private var openConnectFlow: (() -> Void)?
    private var isDemoData: Bool
    private var goalsStore: GoalsStore?
    private var membershipsStore: MembershipsStore?
    private var openMemberships: (() -> Void)?
    private var openProactiveSignal: ((ProactiveSignal) -> Void)?
    private var dismissProactiveSignal: ((ProactiveSignal) -> Void)?

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
        openAnomalyExplainer: ((String) -> Void)? = nil,
        openConnectFlow: (() -> Void)? = nil,
        isDemoData: Bool = false,
        goalsStore: GoalsStore? = nil,
        membershipsStore: MembershipsStore? = nil,
        openMemberships: (() -> Void)? = nil,
        openProactiveSignal: ((ProactiveSignal) -> Void)? = nil,
        dismissProactiveSignal: ((ProactiveSignal) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.iconResolver = iconResolver
        self.openCashFlow = openCashFlow
        self.openGoals = openGoals
        self.openTopCategory = openTopCategory
        self.openNextBill = openNextBill
        self.openAnomalyExplainer = openAnomalyExplainer
        self.openConnectFlow = openConnectFlow
        self.isDemoData = isDemoData
        self.goalsStore = goalsStore
        self.membershipsStore = membershipsStore
        self.openMemberships = openMemberships
        self.openProactiveSignal = openProactiveSignal
        self.dismissProactiveSignal = dismissProactiveSignal
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
                if isDemoData {
                    DashboardDemoBanner(
                        tokens: tokens,
                        onConnect: openConnectFlow
                    )
                }
                DashboardHeroRow(
                    widgetState: viewModel.widgetState,
                    currency: defaultCurrency,
                    openCashFlow: openCashFlow,
                    openTopCategory: openTopCategory,
                    openNextBill: openNextBill,
                    iconResolver: iconResolver
                )
                DashboardHeroRow2(
                    widgetState: viewModel.widgetState,
                    currency: defaultCurrency,
                    monthSpendTotal: monthSpendTotal,
                    monthDayCount: monthDayCount,
                    monthSparkline: monthSparkline,
                    goalsStore: goalsStore,
                    membershipsStore: membershipsStore,
                    openGoals: openGoals,
                    openMemberships: openMemberships,
                    openSpending: openCashFlow
                )
                if !viewModel.proactiveSignals.isEmpty {
                    DashboardProactiveStrip(
                        signals: viewModel.proactiveSignals,
                        tokens: tokens,
                        onTap: openProactiveSignal,
                        onDismiss: dismissProactiveSignal
                    )
                }
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
                isDemoData: isDemoData,
                goalsStore: goalsStore,
                openGoals: openGoals,
                openAnomalyExplainer: openAnomalyExplainer
            )
            .frame(width: 320)
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
            if isDemoData {
                DashboardDemoBanner(
                    tokens: tokens,
                    onConnect: openConnectFlow
                )
            }
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    DashboardHeroRow(
                        widgetState: viewModel.widgetState,
                        currency: defaultCurrency,
                        openCashFlow: openCashFlow,
                        openTopCategory: openTopCategory,
                        openNextBill: openNextBill,
                        iconResolver: iconResolver
                    )
                    DashboardHeroRow2(
                        widgetState: viewModel.widgetState,
                        currency: defaultCurrency,
                        monthSpendTotal: monthSpendTotal,
                        monthDayCount: monthDayCount,
                        monthSparkline: monthSparkline,
                        goalsStore: goalsStore,
                        membershipsStore: membershipsStore,
                        openGoals: openGoals,
                        openMemberships: openMemberships,
                        openSpending: openCashFlow
                    )
                }
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            if !viewModel.proactiveSignals.isEmpty {
                DashboardProactiveStrip(
                    signals: viewModel.proactiveSignals,
                    tokens: tokens,
                    onTap: openProactiveSignal,
                    onDismiss: dismissProactiveSignal
                )
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

    // MARK: - Month aggregates (second hero row)
    //
    // Walks the dashboard's entry set to derive the month-to-date spend
    // total, the number of days elapsed, and a per-day mini-sparkline
    // for the second hero row's THIS MONTH card. Deterministic against
    // a pinned reference date so demo snapshots stay stable.

    private var monthEntries: [DashboardEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let comps = cal.dateComponents([.year, .month], from: today)
        return viewModel.entries.filter { e in
            let d = e.transaction.date
            let dc = cal.dateComponents([.year, .month], from: d)
            return dc.year == comps.year && dc.month == comps.month
        }
    }

    private var monthSpendTotal: Decimal {
        monthEntries.reduce(Decimal.zero) { acc, e in
            guard let amount = e.transaction.amount, amount < 0, !e.transaction.pending else {
                return acc
            }
            return acc + abs(amount)
        }
    }

    private var monthDayCount: Int {
        let cal = Calendar.current
        return cal.component(.day, from: Date())
    }

    /// Per-day spend totals for the current month, oldest first.
    /// Capped at 12 buckets — the mini-bar chart inside the hero card
    /// is only 18pt tall, so more bars would just turn into hair.
    private var monthSparkline: [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = monthDayCount
        var buckets: [Double] = Array(repeating: 0, count: max(days, 1))
        for e in monthEntries {
            guard let amount = e.transaction.amount, amount < 0, !e.transaction.pending else {
                continue
            }
            let dayOfMonth = cal.component(.day, from: e.transaction.date)
            let idx = max(0, min(dayOfMonth - 1, buckets.count - 1))
            buckets[idx] += abs((amount as NSDecimalNumber).doubleValue)
            _ = today
        }
        // Cap to 12 bars; bucket the trailing 11 days flush, take
        // earlier days as a mean.
        if buckets.count <= 12 { return buckets }
        let recent = Array(buckets.suffix(11))
        let earlierMean = buckets.dropLast(11).reduce(0, +) / Double(buckets.count - 11)
        return [earlierMean] + recent
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
                merchant: "Sample Streaming Service",
                amount: Decimal(string: "22.99")!,
                dueDate: tomorrow
            ),
            DashboardWidgetReducer.Upcoming(
                merchant: "Sample Music Subscription",
                amount: Decimal(string: "16.99")!,
                dueDate: three
            ),
            DashboardWidgetReducer.Upcoming(
                merchant: "Sample Cloud Storage",
                amount: Decimal(string: "9.99")!,
                dueDate: five
            )
        ]
    }

    /// Default AI narration so the inspector card paints in the demo.
    /// Phrased generically so it never reads as real spending analysis.
    public static let demoAINarration = DashboardWidgetReducer.AINarration(
        sentence: "Sample narration — your real spending insights will appear here once accounts are connected.",
        cta: "Connect accounts"
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
