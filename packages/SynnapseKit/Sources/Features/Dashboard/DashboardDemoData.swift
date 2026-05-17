import Foundation
import Models

/// Seed data for the Dashboard inbox. Mirrors the merchant strings the
/// Copilot reference screenshot shows (AFFIRM, KLARNA, ZELLE, William
/// & Mary Payroll, Discover, Platinum Visa, PayPal) and fans across
/// four accounts so the right-inspector "accounts touched" line is
/// non-trivial.
///
/// The data is authored relative to a pinned `referenceDate` so the
/// snapshot tests get deterministic "May 15th" / "May 14th" headers
/// regardless of when the test runs. Callers that want today-relative
/// data pass `Date()`; the iOS demo wiring does this.
public enum DashboardDemoData {

    /// 2026-05-15 18:00 UTC — pinned so demo grouping reads as a
    /// 7-day window ending on a Friday. Snapshot tests assume this.
    public static let referenceDate: Date = {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")
        c.year = 2026; c.month = 5; c.day = 15
        c.hour = 18; c.minute = 0
        return c.date!
    }()

    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// Four account ids — Discover credit, Platinum Visa credit,
    /// Adv+ Banking depository, PayPal balance. Names match the
    /// sidebar's "MY ACCOUNTS" list in the Copilot screenshot.
    public enum Account: String, CaseIterable {
        case discoverCC = "acct_discover"
        case platinumVisa = "acct_platinum_visa"
        case advPlusBanking = "acct_adv_plus_banking"
        case payPal = "acct_paypal"

        public var displayName: String {
            switch self {
            case .discoverCC:       return "Discover it Card"
            case .platinumVisa:     return "Platinum Visa"
            case .advPlusBanking:   return "Adv Plus Banking"
            case .payPal:           return "PayPal"
            }
        }
    }

    /// Full inbox: at least 30 un-reviewed rows across 7 days and
    /// every account, plus a handful of already-reviewed rows so
    /// the underlying list isn't all inbox.
    public static var previewEntries: [DashboardEntry] {
        build(referenceDate: referenceDate, calendar: calendar)
    }

    /// Build inbox entries relative to a caller-supplied "today".
    /// Used by the iOS shell so the bottom-of-week-old "May 7th"
    /// section never goes empty even as the clock advances past
    /// the pinned demo date.
    public static func entries(
        relativeTo today: Date,
        calendar: Calendar = .current
    ) -> [DashboardEntry] {
        build(referenceDate: today, calendar: calendar)
    }

    // MARK: - Internal builder

    private static func build(
        referenceDate: Date, calendar: Calendar
    ) -> [DashboardEntry] {
        var out: [DashboardEntry] = []
        // Helper to lay down a row at `daysAgo` from `referenceDate`,
        // at `hour:minute` within that day so ordering inside a day
        // is deterministic.
        func add(
            daysAgo: Int, hour: Int, minute: Int,
            merchant: String, description: String?,
            amount: Decimal, category: String,
            account: Account, pending: Bool = false,
            reviewed: Bool = false
        ) {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate)!
            var c = calendar.dateComponents([.year, .month, .day], from: day)
            c.hour = hour; c.minute = minute
            let date = calendar.date(from: c)!
            let id = "tx_demo_\(out.count + 1)_\(daysAgo)"
            let tx = Transaction(
                id: id,
                accountId: account.rawValue,
                accountName: account.displayName,
                amount: amount,
                currency: "USD",
                date: date,
                name: merchant,
                merchantName: merchant,
                category: .knownCategory(category),
                subcategory: nil,
                pending: pending
            )
            out.append(
                DashboardEntry(
                    transaction: tx,
                    reviewed: reviewed,
                    description: description
                )
            )
        }

        // --- May 15th (today) — 6 rows ---------------------------------
        add(daysAgo: 0, hour: 17, minute: 42,
            merchant: "PANERA BREAD",
            description: "Purchase Panera Bread #1042",
            amount: -14.65, category: "RESTAURANTS",
            account: .discoverCC)
        add(daysAgo: 0, hour: 15, minute: 10,
            merchant: "ANTHROPIC",
            description: "Recurring · Claude Pro",
            amount: -20.00, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 0, hour: 12, minute: 30,
            merchant: "AFFIRM * PAY R3H",
            description: "Affirm payment · order R3H",
            amount: -125.78, category: "LOANS",
            account: .advPlusBanking)
        add(daysAgo: 0, hour: 11, minute: 5,
            merchant: "WHOLE FOODS MKT",
            description: "Purchase Whole Foods #10412",
            amount: -86.42, category: "GROCERIES",
            account: .discoverCC)
        add(daysAgo: 0, hour: 9, minute: 50,
            merchant: "STARBUCKS",
            description: "Purchase Starbucks #2310",
            amount: -6.75, category: "RESTAURANTS",
            account: .discoverCC, pending: true)
        add(daysAgo: 0, hour: 8, minute: 22,
            merchant: "NETFLIX.COM",
            description: "Recurring · Netflix Premium",
            amount: -22.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)

        // --- May 14th — 5 rows ----------------------------------------
        add(daysAgo: 1, hour: 20, minute: 4,
            merchant: "CHIPOTLE",
            description: "Purchase Chipotle #882",
            amount: -16.30, category: "RESTAURANTS",
            account: .discoverCC)
        add(daysAgo: 1, hour: 17, minute: 33,
            merchant: "AMAZON.COM",
            description: "Order 112-3490188-001",
            amount: -64.20, category: "SHOPPING",
            account: .platinumVisa)
        add(daysAgo: 1, hour: 14, minute: 12,
            merchant: "AFFIRM * NETO",
            description: "Affirm payment · order NETO",
            amount: -57.40, category: "LOANS",
            account: .advPlusBanking)
        add(daysAgo: 1, hour: 10, minute: 0,
            merchant: "ACH CREDIT WILLIAM & MARY",
            description: "ACH CREDIT · WILLIAM & MARY PAYROLL",
            amount: 3460.82, category: "INCOME",
            account: .advPlusBanking)
        add(daysAgo: 1, hour: 8, minute: 45,
            merchant: "SPOTIFY USA",
            description: "Recurring · Spotify Premium Family",
            amount: -16.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)

        // --- May 13th — 4 rows ----------------------------------------
        add(daysAgo: 2, hour: 19, minute: 1,
            merchant: "UBER TRIP",
            description: "Uber · 4.2 mi · 12 min",
            amount: -18.92, category: "TRANSPORT",
            account: .discoverCC)
        add(daysAgo: 2, hour: 15, minute: 28,
            merchant: "NIKE.COM",
            description: "Order #N210912",
            amount: -129.50, category: "CLOTHING",
            account: .platinumVisa)
        add(daysAgo: 2, hour: 11, minute: 18,
            merchant: "TRADER JOE'S",
            description: "Purchase TJ's #455",
            amount: -42.10, category: "GROCERIES",
            account: .advPlusBanking)
        add(daysAgo: 2, hour: 9, minute: 0,
            merchant: "OPENAI",
            description: "Recurring · ChatGPT Plus",
            amount: -20.00, category: "SUBSCRIPTIONS",
            account: .platinumVisa)

        // --- May 12th — 4 rows ----------------------------------------
        add(daysAgo: 3, hour: 21, minute: 50,
            merchant: "AMC THEATRES",
            description: "AMC #2381 · 2 adult tickets",
            amount: -28.40, category: "ENTERTAINMENT",
            account: .discoverCC)
        add(daysAgo: 3, hour: 16, minute: 22,
            merchant: "ZELLE TO ANTONIO MASTROPAOLO",
            description: "Zelle payment",
            amount: -200.00, category: "TRANSFER",
            account: .advPlusBanking)
        add(daysAgo: 3, hour: 12, minute: 10,
            merchant: "GOLDS GYM",
            description: "Recurring · monthly membership",
            amount: -39.99, category: "PERSONAL CARE",
            account: .platinumVisa)
        add(daysAgo: 3, hour: 8, minute: 35,
            merchant: "SHAKE SHACK",
            description: "Purchase Shake Shack #21",
            amount: -19.85, category: "RESTAURANTS",
            account: .discoverCC)

        // --- May 11th — 4 rows ----------------------------------------
        add(daysAgo: 4, hour: 18, minute: 12,
            merchant: "KLARNA *KLARN",
            description: "Klarna · order 28201",
            amount: -45.00, category: "LOANS",
            account: .advPlusBanking)
        add(daysAgo: 4, hour: 14, minute: 4,
            merchant: "APPLE.COM/BILL",
            description: "Recurring · iCloud+ 2TB",
            amount: -9.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 4, hour: 11, minute: 56,
            merchant: "ZARA",
            description: "Purchase Zara #1102",
            amount: -76.30, category: "CLOTHING",
            account: .discoverCC)
        add(daysAgo: 4, hour: 8, minute: 0,
            merchant: "KROGER",
            description: "Purchase Kroger #882",
            amount: -94.18, category: "GROCERIES",
            account: .advPlusBanking)

        // --- May 9th (skip May 10) — 3 rows ---------------------------
        add(daysAgo: 6, hour: 19, minute: 30,
            merchant: "SIRIUSXM",
            description: "Recurring · SiriusXM",
            amount: -16.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 6, hour: 13, minute: 45,
            merchant: "VENMO CASHOUT",
            description: "Venmo · cash-out to bank",
            amount: 120.00, category: "TRANSFER",
            account: .payPal)
        add(daysAgo: 6, hour: 9, minute: 22,
            merchant: "SUPERCUTS",
            description: "Purchase Supercuts #91",
            amount: -28.00, category: "PERSONAL CARE",
            account: .discoverCC)

        // --- May 8th — 4 rows -----------------------------------------
        add(daysAgo: 7, hour: 20, minute: 8,
            merchant: "NYTIMES",
            description: "Recurring · NYT Cooking + News",
            amount: -25.00, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 7, hour: 15, minute: 4,
            merchant: "STEAM PURCHASE",
            description: "Steam · 1 item",
            amount: -29.99, category: "ENTERTAINMENT",
            account: .discoverCC)
        add(daysAgo: 7, hour: 12, minute: 22,
            merchant: "ATM FEE",
            description: "Non-network ATM fee",
            amount: -3.50, category: "FEES",
            account: .advPlusBanking)
        add(daysAgo: 7, hour: 10, minute: 30,
            merchant: "WEGMANS",
            description: "Purchase Wegmans #102",
            amount: -58.92, category: "GROCERIES",
            account: .advPlusBanking)

        // --- Already-reviewed rows (so the inbox total isn't the
        // same as the ledger total). These should not appear in
        // sections; they exist so the footer "N of TOTAL" reads
        // realistically and tests can verify the filter.
        add(daysAgo: 8, hour: 12, minute: 0,
            merchant: "ADIDAS",
            description: "Purchase Adidas #312",
            amount: -84.00, category: "CLOTHING",
            account: .discoverCC,
            reviewed: true)
        add(daysAgo: 9, hour: 12, minute: 0,
            merchant: "UNIQLO",
            description: "Purchase Uniqlo #44",
            amount: -51.20, category: "CLOTHING",
            account: .platinumVisa,
            reviewed: true)
        add(daysAgo: 9, hour: 9, minute: 0,
            merchant: "BREAD FINANCIAL",
            description: "Bread Financial payment",
            amount: -110.00, category: "LOANS",
            account: .advPlusBanking,
            reviewed: true)

        return out
    }

    /// Believable ledger total. The screenshot's footer reads
    /// "29 of 3204"; we surface the same shape so the dashboard
    /// renders an in-context count.
    public static let ledgerTotal: Int = 3204
}
