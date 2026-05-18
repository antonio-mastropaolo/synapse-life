import Foundation
import Testing
@testable import Features
@testable import Models

/// Behavioural contract for [[DashboardViewModel]].
///
/// The view model owns three responsibilities: (1) filter to
/// `reviewed == false` for the inbox projection, (2) bucket entries
/// by day with deterministic ordering, (3) flip selected rows to
/// reviewed in a single mutation and clear the selection. Each test
/// pins the calendar to UTC so day boundaries don't drift on CI.
@MainActor
@Suite("DashboardViewModel")
struct DashboardViewModelTests {

    // MARK: - Fixture helpers

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Pinned reference: 2026-05-15T12:00:00Z.
    private static let pinnedToday: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 15
        c.hour = 12; c.minute = 0
        c.calendar = utcCalendar; c.timeZone = TimeZone(identifier: "UTC")
        return c.date!
    }()

    private func makeEntry(
        id: String,
        daysAgo: Int,
        hour: Int = 12,
        amount: Decimal = -10,
        reviewed: Bool = false,
        category: String = "RESTAURANTS"
    ) -> DashboardEntry {
        let day = Self.utcCalendar.date(
            byAdding: .day, value: -daysAgo, to: Self.pinnedToday
        )!
        var c = Self.utcCalendar.dateComponents([.year, .month, .day], from: day)
        c.hour = hour
        let date = Self.utcCalendar.date(from: c)!
        let tx = Transaction(
            id: id,
            accountId: "acct_test",
            accountName: "Test Account",
            amount: amount,
            currency: "USD",
            date: date,
            name: "Merchant \(id)",
            merchantName: "Merchant \(id)",
            category: .knownCategory(category),
            subcategory: nil,
            pending: false
        )
        return DashboardEntry(transaction: tx, reviewed: reviewed, description: nil)
    }

    private func makeViewModel(
        _ entries: [DashboardEntry],
        total: Int? = nil
    ) -> DashboardViewModel {
        DashboardViewModel(
            entries: entries,
            ledgerTotal: total,
            calendar: Self.utcCalendar,
            referenceDate: Self.pinnedToday,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    // MARK: - Reviewed filter

    @Test("inbox excludes reviewed entries")
    func excludesReviewed() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0, reviewed: false),
            makeEntry(id: "b", daysAgo: 0, reviewed: true),
            makeEntry(id: "c", daysAgo: 1, reviewed: false)
        ])
        let ids = vm.sections.flatMap { $0.entries.map(\.id) }
        #expect(ids == ["a", "c"])
    }

    @Test("footer count uses unreviewed count")
    func footerCount() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0),
            makeEntry(id: "b", daysAgo: 0, reviewed: true),
            makeEntry(id: "c", daysAgo: 1)
        ], total: 3204)
        #expect(vm.footerCountText == "2 of 3204")
    }

    // MARK: - Date bucketing

    @Test("entries are grouped by start-of-day, newest day first")
    func groupedByDay() {
        let vm = makeViewModel([
            makeEntry(id: "today_late",  daysAgo: 0, hour: 20),
            makeEntry(id: "today_early", daysAgo: 0, hour: 8),
            makeEntry(id: "yesterday",   daysAgo: 1),
            makeEntry(id: "lastweek",    daysAgo: 7)
        ])
        #expect(vm.sections.count == 3)
        #expect(vm.sections[0].entries.map(\.id) == ["today_late", "today_early"])
        #expect(vm.sections[1].entries.map(\.id) == ["yesterday"])
        #expect(vm.sections[2].entries.map(\.id) == ["lastweek"])
    }

    @Test("section header has English ordinal suffix")
    func headerOrdinals() {
        let vm = makeViewModel([
            // referenceDate is May 15 → "May 15th"
            makeEntry(id: "may15", daysAgo: 0),
            // May 13 → "May 13th"
            makeEntry(id: "may13", daysAgo: 2),
            // May 12 → "May 12th"
            makeEntry(id: "may12", daysAgo: 3),
            // May 1 → daysAgo 14 from May 15 = May 1, "May 1st"
            makeEntry(id: "may01", daysAgo: 14)
        ])
        let titles = vm.sections.map(\.title)
        #expect(titles.contains("May 15th"))
        #expect(titles.contains("May 13th"))
        #expect(titles.contains("May 12th"))
        #expect(titles.contains("May 1st"))
    }

    @Test("ordinal suffix handles 11/12/13 special cases")
    func ordinalSpecialCases() {
        #expect(DashboardViewModel.ordinalSuffix(for: 1)  == "st")
        #expect(DashboardViewModel.ordinalSuffix(for: 2)  == "nd")
        #expect(DashboardViewModel.ordinalSuffix(for: 3)  == "rd")
        #expect(DashboardViewModel.ordinalSuffix(for: 4)  == "th")
        #expect(DashboardViewModel.ordinalSuffix(for: 11) == "th")
        #expect(DashboardViewModel.ordinalSuffix(for: 12) == "th")
        #expect(DashboardViewModel.ordinalSuffix(for: 13) == "th")
        #expect(DashboardViewModel.ordinalSuffix(for: 21) == "st")
        #expect(DashboardViewModel.ordinalSuffix(for: 22) == "nd")
        #expect(DashboardViewModel.ordinalSuffix(for: 23) == "rd")
    }

    // MARK: - Selection + mark reviewed

    @Test("toggleSelection adds and removes ids")
    func toggle() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0),
            makeEntry(id: "b", daysAgo: 0)
        ])
        #expect(!vm.isSelected("a"))
        vm.toggleSelection("a")
        #expect(vm.isSelected("a"))
        #expect(vm.selectionCount == 1)
        vm.toggleSelection("a")
        #expect(!vm.isSelected("a"))
        #expect(vm.selectionCount == 0)
    }

    @Test("markSelectedAsReviewed flips entries and clears selection")
    func markSelected() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0),
            makeEntry(id: "b", daysAgo: 0),
            makeEntry(id: "c", daysAgo: 1)
        ], total: 100)
        vm.toggleSelection("a")
        vm.toggleSelection("c")
        let n = vm.markSelectedAsReviewed()
        #expect(n == 2)
        #expect(vm.selectionCount == 0)
        #expect(vm.entries.first { $0.id == "a" }?.reviewed == true)
        #expect(vm.entries.first { $0.id == "c" }?.reviewed == true)
        #expect(vm.entries.first { $0.id == "b" }?.reviewed == false)
        let inboxIds = vm.sections.flatMap { $0.entries.map(\.id) }
        #expect(inboxIds == ["b"])
        #expect(vm.footerCountText == "1 of 100")
    }

    @Test("markSelectedAsReviewed is a no-op with empty selection")
    func markEmpty() {
        let vm = makeViewModel([makeEntry(id: "a", daysAgo: 0)])
        let n = vm.markSelectedAsReviewed()
        #expect(n == 0)
        #expect(vm.entries.first?.reviewed == false)
    }

    @Test("load replaces entries and resets selection")
    func loadReplaces() {
        let vm = makeViewModel([makeEntry(id: "a", daysAgo: 0)])
        vm.toggleSelection("a")
        #expect(vm.selectionCount == 1)
        vm.load([makeEntry(id: "x", daysAgo: 0)], ledgerTotal: 50)
        #expect(vm.selectionCount == 0)
        #expect(vm.entries.map(\.id) == ["x"])
        #expect(vm.footerCountText == "1 of 50")
    }

    // MARK: - Net this month

    @Test("netThisMonth sums entries in the current month")
    func netThisMonth() {
        // May 2026: include both reviewed and unreviewed; exclude
        // an April row.
        let april = makeEntry(id: "april", daysAgo: 20, amount: -1_000)
        let may1 = makeEntry(id: "may1",   daysAgo: 14, amount: 5_000)
        let may2 = makeEntry(id: "may2",   daysAgo: 1,  amount: -250, reviewed: true)
        let may3 = makeEntry(id: "may3",   daysAgo: 0,  amount: -100)
        let vm = makeViewModel([april, may1, may2, may3])
        // 5000 - 250 - 100 = 4650
        #expect(vm.netThisMonth == Decimal(4650))
    }

    // MARK: - Widget state (M9 hero row)

    @Test("widgetState.unreviewed reflects entries and ledger total")
    func widgetStateUnreviewed() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0),
            makeEntry(id: "b", daysAgo: 0, reviewed: true),
            makeEntry(id: "c", daysAgo: 1)
        ], total: 3204)
        #expect(vm.widgetState.unreviewed.count == 2)
        #expect(vm.widgetState.unreviewed.total == 3204)
    }

    @Test("widgetState.netThisWeek is materialised on init")
    func widgetStateNet() {
        let vm = makeViewModel([
            makeEntry(id: "in", daysAgo: 1, amount: 5_000),
            makeEntry(id: "out", daysAgo: 0, amount: -100)
        ])
        #expect(vm.widgetState.netThisWeek.current == Decimal(4900))
        // No prior-window entries → previous = 0.
        #expect(vm.widgetState.netThisWeek.previous == Decimal(0))
    }

    @Test("widgetState reads upcomingBills and aiSuggestion providers")
    func widgetStateProviders() {
        let cal = Self.utcCalendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Self.pinnedToday)!
        let billProvider: () -> [DashboardWidgetReducer.Upcoming] = {
            [
                DashboardWidgetReducer.Upcoming(
                    merchant: "NETFLIX",
                    amount: Decimal(string: "22.99")!,
                    dueDate: tomorrow
                )
            ]
        }
        let aiProvider: () -> DashboardWidgetReducer.AINarration? = {
            DashboardWidgetReducer.AINarration(sentence: "spending below avg")
        }
        let vm = DashboardViewModel(
            entries: [makeEntry(id: "a", daysAgo: 0)],
            ledgerTotal: 1,
            calendar: cal,
            referenceDate: Self.pinnedToday,
            locale: Locale(identifier: "en_US_POSIX"),
            upcomingBillsProvider: billProvider,
            anomaliesProvider: { [] },
            aiSuggestionProvider: aiProvider
        )
        #expect(vm.widgetState.nextBill?.upcoming.merchant == "NETFLIX")
        #expect(vm.widgetState.nextBill?.urgency == .tomorrow)
        #expect(vm.widgetState.aiSuggestion?.sentence == "spending below avg")
    }

    // MARK: - markAll / skipAll

    @Test("markAll flips every unreviewed entry")
    func markAll() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0),
            makeEntry(id: "b", daysAgo: 0, reviewed: true),
            makeEntry(id: "c", daysAgo: 1)
        ], total: 100)
        // Sanity: selection is unused; markAll touches every unreviewed
        // row regardless.
        let n = vm.markAll()
        #expect(n == 2)
        #expect(vm.entries.allSatisfy { $0.reviewed })
        #expect(vm.sections.isEmpty)
        #expect(vm.footerCountText == "0 of 100")
    }

    @Test("skipAll clears selection without flipping review bits")
    func skipAll() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0),
            makeEntry(id: "b", daysAgo: 0)
        ])
        vm.toggleSelection("a")
        vm.toggleSelection("b")
        #expect(vm.selectionCount == 2)
        vm.skipAll()
        #expect(vm.selectionCount == 0)
        // Review bits unchanged.
        #expect(vm.entries.allSatisfy { !$0.reviewed })
    }

    // MARK: - Inline expansion

    @Test("toggleExpanded sets and clears expandedRowId")
    func toggleExpanded() {
        let vm = makeViewModel([
            makeEntry(id: "a", daysAgo: 0),
            makeEntry(id: "b", daysAgo: 0)
        ])
        #expect(vm.expandedRowId == nil)
        vm.toggleExpanded("a")
        #expect(vm.expandedRowId == "a")
        // Tapping a different row switches the expansion.
        vm.toggleExpanded("b")
        #expect(vm.expandedRowId == "b")
        // Tapping the same row collapses.
        vm.toggleExpanded("b")
        #expect(vm.expandedRowId == nil)
    }

    @Test("recentSameMerchant returns peers excluding the target row")
    func recentSameMerchantPeers() {
        // makeEntry seeds merchantName = "Merchant <id>". To get a
        // peer set we author entries with hand-built transactions
        // that share the same merchant name.
        func merchantEntry(id: String, daysAgo: Int, merchant: String) -> DashboardEntry {
            let day = Self.utcCalendar.date(
                byAdding: .day, value: -daysAgo, to: Self.pinnedToday
            )!
            var c = Self.utcCalendar.dateComponents([.year, .month, .day], from: day)
            c.hour = 12
            let date = Self.utcCalendar.date(from: c)!
            let tx = Transaction(
                id: id,
                accountId: "acct_test",
                accountName: "Test Account",
                amount: -10,
                currency: "USD",
                date: date,
                name: merchant,
                merchantName: merchant,
                category: .knownCategory("RESTAURANTS"),
                subcategory: nil,
                pending: false
            )
            return DashboardEntry(transaction: tx, reviewed: false, description: nil)
        }
        let vm = makeViewModel([
            merchantEntry(id: "n1", daysAgo: 0, merchant: "NETFLIX"),
            merchantEntry(id: "n2", daysAgo: 7, merchant: "NETFLIX"),
            merchantEntry(id: "n3", daysAgo: 14, merchant: "NETFLIX"),
            merchantEntry(id: "n4", daysAgo: 21, merchant: "NETFLIX"),
            merchantEntry(id: "k1", daysAgo: 1, merchant: "KROGER")
        ])
        let peers = vm.recentSameMerchant(for: "n1", limit: 3)
        #expect(peers.count == 3)
        #expect(peers.map(\.id) == ["n2", "n3", "n4"])
        // Different merchant returns no peers (Kroger only has itself).
        let krogerPeers = vm.recentSameMerchant(for: "k1")
        #expect(krogerPeers.isEmpty)
    }
}
