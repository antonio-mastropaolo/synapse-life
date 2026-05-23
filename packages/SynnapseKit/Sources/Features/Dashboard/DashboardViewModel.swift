import Foundation
import Observation
import Models

/// State machine for the Dashboard inbox.
///
/// Modelled after [[FinanceTransactionsViewModel]] but deliberately
/// thinner: there is no remote endpoint behind it today. The dashboard
/// projects entries that already live in the local ledger and applies
/// the `reviewed` overlay on top. When the server contract lands, the
/// `load` entry point becomes a network call and the rest of the view
/// model stays the same.
@MainActor
@Observable
public final class DashboardViewModel {

    /// All entries known to the dashboard, in newest-first order.
    /// Stored as the source of truth; `sections` is a projection.
    public private(set) var entries: [DashboardEntry]

    /// Total transactions in the underlying ledger — used to render
    /// the "N of TOTAL" footer string. Defaults to `entries.count`
    /// so the demo data sets a believable denominator without
    /// requiring a separate ledger fetch.
    public private(set) var ledgerTotal: Int

    /// Multi-select state, keyed by `DashboardEntry.id`. The view
    /// drives this through per-row checkboxes; `markSelectedAsReviewed`
    /// flips the entries and clears the selection in one shot.
    public private(set) var selection: Set<String> = []

    /// Cached projection. Recomputed when `entries` or the calendar
    /// changes, never per render.
    public private(set) var sections: [DashboardSection] = []

    /// Calendar used for day bucketing. Defaults to the user's
    /// current calendar; tests inject a UTC calendar so day
    /// boundaries are deterministic.
    private let calendar: Calendar

    /// Reference "today" for relative header strings. In production
    /// this is `Date()`; tests pin it so "May 15th" doesn't drift.
    private let referenceDate: Date

    /// Header formatter — month name + day with ordinal suffix
    /// ("May 15th"). The formatter is constructed once and reused.
    private let headerFormatter: DateFormatter

    /// Inline-expansion state. Exactly one row may be expanded at a
    /// time — Copilot's pattern. Tapping an already-expanded row
    /// collapses it.
    public private(set) var expandedRowId: String?

    /// Proactive feed (Phase 4) the inbox surfaces above the review queue:
    /// upcoming bills, brand-new recurrings, anomalous spend. Sourced from the
    /// durable `ProactiveNotificationStore` via `AppCore` and set through
    /// `setProactiveSignals`. Empty by default so existing call sites (and the
    /// snapshot fixtures) render the dashboard exactly as before — the strip
    /// only appears once the analyzer has surfaced something.
    public private(set) var proactiveSignals: [ProactiveSignal] = []

    // MARK: - Widget providers (M9 hero row)

    /// Upcoming-bills provider. The integrator wires this to
    /// `RecurringDetector`; the dashboard reads it once on init and
    /// again on each `load(_:)` so the NEXT BILL hero card stays in
    /// sync without the dashboard knowing the detector exists.
    private let upcomingBillsProvider: () -> [DashboardWidgetReducer.Upcoming]

    /// Anomalies provider — top-N flagged rows. The integrator wires
    /// this to `AnomalyExplainerReducer`. Empty by default; the
    /// inspector mini-list collapses when empty.
    private let anomaliesProvider: () -> [DashboardEntry]

    /// AI suggestion provider — single-sentence digest. The
    /// integrator wires this to `DigestReducer`; nil collapses the
    /// inspector AI card entirely.
    private let aiSuggestionProvider: () -> DashboardWidgetReducer.AINarration?

    /// Cached widget state, materialised once per `entries`/provider
    /// read. The view binds to this so each card avoids re-running
    /// its reducer on every render. Recomputed in `reproject()`.
    public private(set) var widgetState: WidgetState = .empty

    public init(
        entries: [DashboardEntry] = [],
        ledgerTotal: Int? = nil,
        calendar: Calendar = .current,
        referenceDate: Date = Date(),
        locale: Locale = .current,
        upcomingBillsProvider: @escaping () -> [DashboardWidgetReducer.Upcoming] = { [] },
        anomaliesProvider: @escaping () -> [DashboardEntry] = { [] },
        aiSuggestionProvider: @escaping () -> DashboardWidgetReducer.AINarration? = { nil }
    ) {
        self.entries = entries
        self.ledgerTotal = ledgerTotal ?? entries.count
        self.calendar = calendar
        self.referenceDate = referenceDate
        self.upcomingBillsProvider = upcomingBillsProvider
        self.anomaliesProvider = anomaliesProvider
        self.aiSuggestionProvider = aiSuggestionProvider

        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        // "May 15th" — month spelled out, day with ordinal. Ordinal
        // suffixes are produced manually because `DateFormatter` does
        // not expose a token for ordinal day-of-month; see
        // `formatHeader(for:)` below.
        f.dateFormat = "MMMM d"
        self.headerFormatter = f

        reproject()
    }

    // MARK: - Mutation

    /// Replace the entire entry set (used by `refresh()` once the
    /// server contract lands; today the iOS app seeds entries at
    /// init time from `DashboardDemoData`).
    public func load(_ entries: [DashboardEntry], ledgerTotal: Int? = nil) {
        self.entries = entries
        self.ledgerTotal = ledgerTotal ?? entries.count
        // Selection is reset on a full reload — a row that's no
        // longer in the inbox cannot remain selected.
        self.selection = []
        reproject()
    }

    /// Flip the selection for a single row. The toggle is idempotent
    /// against a missing entry (no crash if the id has been removed
    /// between user tap and dispatch).
    /// Replace the proactive feed. Called by `AppCore` after a
    /// `ProactiveAnalyzer` pass writes to the store and reads back
    /// `notifications.recent()`. Pure assignment — no reprojection needed since
    /// the feed renders independently of the transaction sections.
    public func setProactiveSignals(_ signals: [ProactiveSignal]) {
        proactiveSignals = signals
    }

    public func toggleSelection(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    /// Whether a row id is currently selected. The view passes this
    /// straight into the checkbox binding.
    public func isSelected(_ id: String) -> Bool {
        selection.contains(id)
    }

    /// Mark every selected entry as reviewed and drop them from the
    /// inbox in one mutation. Returns the count of rows that were
    /// reviewed — the view shows this in a transient confirmation.
    @discardableResult
    public func markSelectedAsReviewed() -> Int {
        guard !selection.isEmpty else { return 0 }
        let touched = selection
        entries = entries.map { entry in
            guard touched.contains(entry.id) else { return entry }
            var copy = entry
            copy.reviewed = true
            return copy
        }
        let n = touched.count
        selection = []
        reproject()
        return n
    }

    /// Convenience for the footer "Mark N as reviewed" button.
    public var selectionCount: Int { selection.count }

    /// Mark every un-reviewed entry as reviewed in a single mutation.
    /// Returns the count of rows touched. Used by the action ribbon's
    /// "Mark all" secondary affordance — the user has audited their
    /// inbox and wants to clear it without per-row selection.
    @discardableResult
    public func markAll() -> Int {
        var touched = 0
        entries = entries.map { entry in
            guard !entry.reviewed else { return entry }
            touched += 1
            var copy = entry
            copy.reviewed = true
            return copy
        }
        selection = []
        reproject()
        return touched
    }

    /// Clear the active selection without flipping any review bits.
    /// Maps to the action-ribbon "Skip all" affordance — the user is
    /// punting on these rows for the session.
    public func skipAll() {
        guard !selection.isEmpty else { return }
        selection = []
    }

    /// Toggle the inline-expanded row. At most one row is expanded at
    /// a time; tapping the currently-expanded row collapses it.
    public func toggleExpanded(_ id: String) {
        if expandedRowId == id {
            expandedRowId = nil
        } else {
            expandedRowId = id
        }
    }

    /// Recent transactions from the same merchant as `entryId`,
    /// excluding the row itself. Returns at most `limit` rows in
    /// newest-first order. The inline expansion uses this to paint
    /// a small peek of prior charges so the user can audit the row
    /// without leaving the dashboard.
    public func recentSameMerchant(
        for entryId: String,
        limit: Int = 3
    ) -> [DashboardEntry] {
        guard let target = entries.first(where: { $0.id == entryId }),
              let merchant = target.transaction.merchantName
        else { return [] }
        return entries
            .filter { $0.id != entryId
                && $0.transaction.merchantName == merchant }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Derived

    /// Footer label: "29 of 3204".
    public var footerCountText: String {
        let unreviewed = entries.filter { !$0.reviewed }.count
        return "\(unreviewed) of \(ledgerTotal)"
    }

    /// Net for the month containing `referenceDate`, across all
    /// entries (reviewed or not). Copilot shows this as a large
    /// green number in the right inspector — it is a *ledger*
    /// figure, not a review-queue figure, so we deliberately do
    /// not filter by `reviewed`.
    public var netThisMonth: Decimal {
        let comps = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let monthStart = calendar.date(from: comps),
              let monthEnd = calendar.date(
                byAdding: .month, value: 1, to: monthStart
              )
        else { return 0 }
        var total: Decimal = 0
        for entry in entries {
            let date = entry.transaction.date
            guard date >= monthStart, date < monthEnd,
                  let amount = entry.transaction.amount else { continue }
            total += amount
        }
        return total
    }

    // MARK: - Projection

    /// Rebuild `sections` from `entries`. Filtered to un-reviewed,
    /// grouped by start-of-day, newest day first; within a day
    /// rows preserve their incoming order (already newest-first
    /// at the entry level).
    private func reproject() {
        let unreviewed = entries.filter { !$0.reviewed }
        // Bucket by start-of-day in the view model's calendar.
        var buckets: [Date: [DashboardEntry]] = [:]
        for entry in unreviewed {
            let day = calendar.startOfDay(for: entry.transaction.date)
            buckets[day, default: []].append(entry)
        }
        let orderedDays = buckets.keys.sorted(by: >)
        self.sections = orderedDays.map { day in
            DashboardSection(
                day: day,
                title: formatHeader(for: day),
                entries: buckets[day] ?? []
            )
        }
        recomputeWidgetState()
    }

    /// Materialise the widget hero state from the current `entries`
    /// and the three injected providers. Called from `reproject()`
    /// so the cards stay aligned with the list.
    private func recomputeWidgetState() {
        let net = DashboardWidgetReducer.netThisWeek(
            entries: entries,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let unreviewed = DashboardWidgetReducer.unreviewedCount(
            entries: entries,
            ledgerTotal: ledgerTotal
        )
        let top = DashboardWidgetReducer.topCategoryThisWeek(
            entries: entries,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let nextBill = DashboardWidgetReducer.nextBill(
            upcoming: upcomingBillsProvider(),
            referenceDate: referenceDate,
            calendar: calendar
        )
        let pulse = DashboardWidgetReducer.spendingPulse(
            entries: entries,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let anomalies = anomaliesProvider()
        let ai = aiSuggestionProvider()
        self.widgetState = WidgetState(
            netThisWeek: net,
            unreviewed: unreviewed,
            topCategory: top,
            nextBill: nextBill,
            spendingPulse: pulse,
            anomalies: anomalies,
            aiSuggestion: ai
        )
    }

    /// "May 15th". Month + day from `headerFormatter`, with the
    /// English ordinal suffix appended. The suffix logic is
    /// English-only by design — Copilot's UI is English and we
    /// match its tone here; a future localisation pass would
    /// replace this with `DateFormatter.formattingContext` and a
    /// `.stringsdict`-driven ordinal.
    private func formatHeader(for day: Date) -> String {
        let base = headerFormatter.string(from: day)
        let dom = calendar.component(.day, from: day)
        return "\(base)\(Self.ordinalSuffix(for: dom))"
    }

    /// English ordinal suffix for day-of-month. 11/12/13 are
    /// special-cased ("11th", not "11st").
    static func ordinalSuffix(for day: Int) -> String {
        let mod100 = day % 100
        if (11...13).contains(mod100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

/// Materialised hero / inspector state. Kept on the view model so
/// every card binds to the same memoised value — no `reduce` runs
/// per render. Recomputed by `reproject()` whenever entries change.
public struct WidgetState: Equatable, Sendable {
    public let netThisWeek: DashboardWidgetReducer.NetThisWeek
    public let unreviewed: DashboardWidgetReducer.UnreviewedCount
    public let topCategory: DashboardWidgetReducer.TopCategory?
    public let nextBill: DashboardWidgetReducer.NextBill?
    public let spendingPulse: DashboardWidgetReducer.SpendingPulse
    public let anomalies: [DashboardEntry]
    public let aiSuggestion: DashboardWidgetReducer.AINarration?

    public static let empty = WidgetState(
        netThisWeek: DashboardWidgetReducer.NetThisWeek(
            current: 0, previous: 0,
            sparkline: Array(repeating: 0, count: 7)
        ),
        unreviewed: DashboardWidgetReducer.UnreviewedCount(count: 0, total: 0),
        topCategory: nil,
        nextBill: nil,
        spendingPulse: DashboardWidgetReducer.SpendingPulse(today: 0, typical: 0),
        anomalies: [],
        aiSuggestion: nil
    )

    public init(
        netThisWeek: DashboardWidgetReducer.NetThisWeek,
        unreviewed: DashboardWidgetReducer.UnreviewedCount,
        topCategory: DashboardWidgetReducer.TopCategory?,
        nextBill: DashboardWidgetReducer.NextBill?,
        spendingPulse: DashboardWidgetReducer.SpendingPulse,
        anomalies: [DashboardEntry],
        aiSuggestion: DashboardWidgetReducer.AINarration?
    ) {
        self.netThisWeek = netThisWeek
        self.unreviewed = unreviewed
        self.topCategory = topCategory
        self.nextBill = nextBill
        self.spendingPulse = spendingPulse
        self.anomalies = anomalies
        self.aiSuggestion = aiSuggestion
    }
}
