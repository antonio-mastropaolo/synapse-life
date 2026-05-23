import Foundation
import Testing
@testable import Features
@testable import Models

/// Pure-function contract for [[DashboardWidgetReducer]].
///
/// Every test pins a UTC calendar and a fixed reference date so the
/// 7-day windows are deterministic. Decimals are constructed via
/// integers or `Decimal(string:)` — never via `Decimal(literal:)` —
/// to dodge the binary-floating-point round-trip artefact documented
/// in `decimal-from-double`.
@MainActor
@Suite("DashboardWidgetReducer")
struct DashboardWidgetReducerTests {

    // MARK: - Fixture

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-05-15T12:00:00Z
    private static let pinnedToday: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 15
        c.hour = 12; c.minute = 0
        c.calendar = utcCalendar; c.timeZone = TimeZone(identifier: "UTC")
        return c.date!
    }()

    private static func date(daysAgo: Int, hour: Int = 12) -> Date {
        let cal = utcCalendar
        let base = cal.date(byAdding: .day, value: -daysAgo, to: pinnedToday)!
        var c = cal.dateComponents([.year, .month, .day], from: base)
        c.hour = hour
        return cal.date(from: c)!
    }

    private static func entry(
        id: String,
        daysAgo: Int,
        amount: Decimal,
        category: String = "RESTAURANTS",
        reviewed: Bool = false
    ) -> DashboardEntry {
        let tx = Transaction(
            id: id,
            accountId: "a",
            accountName: "Acct",
            amount: amount,
            currency: "USD",
            date: date(daysAgo: daysAgo),
            name: id,
            merchantName: id,
            category: .knownCategory(category),
            subcategory: nil,
            pending: false
        )
        return DashboardEntry(transaction: tx, reviewed: reviewed, description: nil)
    }

    // MARK: - netThisWeek

    @Test("netThisWeek sums signed amounts in a 7-day window")
    func netThisWeekSumsWindow() {
        // Inside window (last 7 days, including today): +5000, -100,
        // -250 (reviewed) → 4650 net.
        // Outside window (8+ days ago): -1000.
        let entries = [
            Self.entry(id: "income",  daysAgo: 1, amount: 5_000),
            Self.entry(id: "today",   daysAgo: 0, amount: -100),
            Self.entry(id: "rev",     daysAgo: 2, amount: -250, reviewed: true),
            Self.entry(id: "old",     daysAgo: 9, amount: -1_000)
        ]
        let result = DashboardWidgetReducer.netThisWeek(
            entries: entries,
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        #expect(result.current == Decimal(4650))
    }

    @Test("netThisWeek computes the prior 7-day window separately")
    func netThisWeekPriorWindow() {
        // Prior window: days 7..13 ago. 8 days ago: -200. 10 days ago: -300.
        // 14 days ago is outside (boundary is *exclusive* at 14).
        let entries = [
            Self.entry(id: "p1",   daysAgo: 8,  amount: -200),
            Self.entry(id: "p2",   daysAgo: 10, amount: -300),
            Self.entry(id: "out",  daysAgo: 14, amount: -50),
            Self.entry(id: "cur",  daysAgo: 0,  amount: -10)
        ]
        let result = DashboardWidgetReducer.netThisWeek(
            entries: entries,
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        #expect(result.previous == Decimal(-500))
        #expect(result.current == Decimal(-10))
        #expect(result.delta == Decimal(490))
    }

    @Test("netThisWeek produces a 7-bucket sparkline, oldest first")
    func netThisWeekSparkline() {
        // Today: -10. 3 days ago: +20. 6 days ago: -5. Everything else
        // is empty.
        let entries = [
            Self.entry(id: "t",   daysAgo: 0, amount: -10),
            Self.entry(id: "t3",  daysAgo: 3, amount: 20),
            Self.entry(id: "t6",  daysAgo: 6, amount: -5)
        ]
        let result = DashboardWidgetReducer.netThisWeek(
            entries: entries,
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        // Buckets are oldest first: -6 .. 0.
        #expect(result.sparkline.count == 7)
        #expect(result.sparkline[0] == Decimal(-5))  // 6d ago
        #expect(result.sparkline[3] == Decimal(20))  // 3d ago
        #expect(result.sparkline[6] == Decimal(-10)) // today
    }

    // MARK: - unreviewedCount

    @Test("unreviewedCount excludes reviewed and keeps total")
    func unreviewedCount() {
        let entries = [
            Self.entry(id: "a", daysAgo: 0, amount: -1),
            Self.entry(id: "b", daysAgo: 0, amount: -1, reviewed: true),
            Self.entry(id: "c", daysAgo: 0, amount: -1)
        ]
        let result = DashboardWidgetReducer.unreviewedCount(
            entries: entries, ledgerTotal: 3204
        )
        #expect(result.count == 2)
        #expect(result.total == 3204)
    }

    // MARK: - topCategoryThisWeek

    @Test("topCategoryThisWeek sums |expense| per category")
    func topCategory() {
        let entries = [
            Self.entry(id: "r1", daysAgo: 0, amount: -50,  category: "RESTAURANTS"),
            Self.entry(id: "r2", daysAgo: 1, amount: -100, category: "RESTAURANTS"),
            Self.entry(id: "g1", daysAgo: 2, amount: -80,  category: "GROCERIES"),
            // Income excluded.
            Self.entry(id: "in", daysAgo: 0, amount: 500,  category: "INCOME"),
            // Outside window excluded.
            Self.entry(id: "ox", daysAgo: 9, amount: -999, category: "RESTAURANTS")
        ]
        let top = DashboardWidgetReducer.topCategoryThisWeek(
            entries: entries,
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        #expect(top != nil)
        #expect(top?.category == .knownCategory("RESTAURANTS"))
        #expect(top?.totalAbsExpense == Decimal(150))
    }

    @Test("topCategoryThisWeek returns nil when no expenses in window")
    func topCategoryEmpty() {
        let entries = [
            Self.entry(id: "in", daysAgo: 0, amount: 500, category: "INCOME")
        ]
        let top = DashboardWidgetReducer.topCategoryThisWeek(
            entries: entries,
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        #expect(top == nil)
    }

    // MARK: - nextBill

    @Test("nextBill picks the soonest future upcoming and tags it today/tomorrow/later")
    func nextBillUrgency() {
        let cal = Self.utcCalendar
        let today = cal.startOfDay(for: Self.pinnedToday)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let inThree = cal.date(byAdding: .day, value: 3, to: today)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let upcoming = [
            // Past — must be skipped.
            DashboardWidgetReducer.Upcoming(
                merchant: "OLD",
                amount: Decimal(string: "9.99")!,
                dueDate: yesterday
            ),
            DashboardWidgetReducer.Upcoming(
                merchant: "FAR",
                amount: Decimal(string: "25.00")!,
                dueDate: inThree
            ),
            DashboardWidgetReducer.Upcoming(
                merchant: "SOON",
                amount: Decimal(string: "12.50")!,
                dueDate: tomorrow
            )
        ]
        let result = DashboardWidgetReducer.nextBill(
            upcoming: upcoming,
            referenceDate: Self.pinnedToday,
            calendar: cal
        )
        #expect(result?.upcoming.merchant == "SOON")
        #expect(result?.urgency == .tomorrow)

        // Now drop the SOON entry → FAR (3 days out) wins.
        let trimmed = upcoming.filter { $0.merchant != "SOON" }
        let later = DashboardWidgetReducer.nextBill(
            upcoming: trimmed,
            referenceDate: Self.pinnedToday,
            calendar: cal
        )
        #expect(later?.upcoming.merchant == "FAR")
        if case .later(let d) = later?.urgency { #expect(d == 3) }
        else { Issue.record("expected .later(3)") }
    }

    @Test("nextBill returns nil when nothing is upcoming")
    func nextBillEmpty() {
        let result = DashboardWidgetReducer.nextBill(
            upcoming: [],
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        #expect(result == nil)
    }

    // MARK: - spendingPulse

    @Test("spendingPulse separates today from the 7-day typical")
    func spendingPulse() {
        let entries = [
            // Today: 25 + 17 = 42 spend
            Self.entry(id: "t1", daysAgo: 0, amount: -25),
            Self.entry(id: "t2", daysAgo: 0, amount: -17),
            // Last 7 days (excluding today): -70 + -70 + -70 + -70 + -70 + -70 + -70 = -490
            Self.entry(id: "p1", daysAgo: 1, amount: -70),
            Self.entry(id: "p2", daysAgo: 2, amount: -70),
            Self.entry(id: "p3", daysAgo: 3, amount: -70),
            Self.entry(id: "p4", daysAgo: 4, amount: -70),
            Self.entry(id: "p5", daysAgo: 5, amount: -70),
            Self.entry(id: "p6", daysAgo: 6, amount: -70),
            Self.entry(id: "p7", daysAgo: 7, amount: -70),
            // Income shouldn't count.
            Self.entry(id: "in", daysAgo: 0, amount: 500, category: "INCOME")
        ]
        let pulse = DashboardWidgetReducer.spendingPulse(
            entries: entries,
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        #expect(pulse.today == Decimal(42))
        // 490 / 7 = 70
        #expect(pulse.typical == Decimal(70))
        // 42 / 70 = 0.6
        #expect(abs(pulse.ratio - 0.6) < 0.0001)
    }

    @Test("spendingPulse ratio caps at 1 when today exceeds typical")
    func spendingPulseCap() {
        let entries = [
            Self.entry(id: "t", daysAgo: 0, amount: -500),
            Self.entry(id: "p", daysAgo: 1, amount: -7) // typical 1.0
        ]
        let pulse = DashboardWidgetReducer.spendingPulse(
            entries: entries,
            referenceDate: Self.pinnedToday,
            calendar: Self.utcCalendar
        )
        #expect(pulse.ratio == 1.0)
    }
}
