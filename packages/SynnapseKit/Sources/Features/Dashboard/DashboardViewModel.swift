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

    public init(
        entries: [DashboardEntry] = [],
        ledgerTotal: Int? = nil,
        calendar: Calendar = .current,
        referenceDate: Date = Date(),
        locale: Locale = .current
    ) {
        self.entries = entries
        self.ledgerTotal = ledgerTotal ?? entries.count
        self.calendar = calendar
        self.referenceDate = referenceDate

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
