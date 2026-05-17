import Foundation
import Testing
@testable import Features
@testable import Models

/// Volume + coverage guarantees for [[DashboardDemoData]].
///
/// The dashboard is meant to render as an inbox of ~30 rows on first
/// paint. If the demo data dropped below that count, the screen would
/// look empty and the "29 of 3204" footer would lie about the inbox
/// size — these tests catch that.
@MainActor
@Suite("DashboardDemoData")
struct DashboardDemoDataTests {

    @Test("at least 30 unreviewed entries are present")
    func unreviewedVolume() {
        let unreviewed = DashboardDemoData.previewEntries.filter { !$0.reviewed }
        #expect(unreviewed.count >= 30,
                "expected ≥30 unreviewed entries, got \(unreviewed.count)")
    }

    @Test("entries span at least 7 distinct days")
    func dayCoverage() {
        let entries = DashboardDemoData.previewEntries.filter { !$0.reviewed }
        let calendar = DashboardDemoData.calendar
        let days = Set(entries.map { calendar.startOfDay(for: $0.transaction.date) })
        #expect(days.count >= 7,
                "expected ≥7 distinct unreviewed days, got \(days.count)")
    }

    @Test("at least 4 distinct accounts are touched")
    func accountCoverage() {
        let entries = DashboardDemoData.previewEntries
        let accounts = Set(entries.compactMap { $0.transaction.accountId })
        #expect(accounts.count >= 4,
                "expected ≥4 distinct accounts, got \(accounts.count)")
    }

    @Test("required category labels are all present in the inbox")
    func categoryCoverage() {
        let entries = DashboardDemoData.previewEntries.filter { !$0.reviewed }
        let categories = Set(entries.map { $0.transaction.category.displayLabel })
        let required: Set<String> = [
            "RESTAURANTS", "SUBSCRIPTIONS", "GROCERIES",
            "LOANS", "CLOTHING", "INCOME", "TRANSFER",
            "PERSONAL CARE", "ENTERTAINMENT"
        ]
        let missing = required.subtracting(categories)
        #expect(missing.isEmpty,
                "missing required categories: \(missing.sorted())")
    }

    @Test("a positive-amount income row exists")
    func hasIncome() {
        let entries = DashboardDemoData.previewEntries
        #expect(entries.contains { ($0.transaction.amount ?? 0) > 0 })
    }

    @Test("at least one pending row exists for the dim treatment")
    func hasPending() {
        let entries = DashboardDemoData.previewEntries
        #expect(entries.contains { $0.transaction.pending })
    }

    @Test("ledger total denominator matches Copilot's 3204 reference")
    func ledgerTotal() {
        #expect(DashboardDemoData.ledgerTotal == 3204)
    }

    @Test("viewModel built from demo data projects deterministic sections")
    func viewModelProjection() {
        let entries = DashboardDemoData.previewEntries
        let vm = DashboardViewModel(
            entries: entries,
            ledgerTotal: DashboardDemoData.ledgerTotal,
            calendar: DashboardDemoData.calendar,
            referenceDate: DashboardDemoData.referenceDate,
            locale: Locale(identifier: "en_US_POSIX")
        )
        // Every section in the projection should have ≥1 row.
        #expect(!vm.sections.isEmpty)
        for s in vm.sections { #expect(!s.entries.isEmpty) }
        // The first section should be "May 15th" — that's the pinned
        // reference date.
        #expect(vm.sections.first?.title == "May 15th")
        // Footer should advertise the demo ledger total.
        #expect(vm.footerCountText.hasSuffix("of 3204"))
    }
}
