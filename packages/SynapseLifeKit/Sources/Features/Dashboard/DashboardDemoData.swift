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
            case .discoverCC:       return "Sample Credit Card"
            case .platinumVisa:     return "Sample Travel Visa"
            case .advPlusBanking:   return "Sample Checking"
            case .payPal:           return "Sample Wallet"
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

        // Every merchant below is an obviously-placeholder string
        // ("Sample Cafe", "Demo Subscription Service", etc). The app
        // is in demo mode until the user connects a real account, and
        // we deliberately avoid real brand names so nothing in the UI
        // can be mistaken for a real transaction.

        // --- Today — 6 rows ---------------------------------------------
        add(daysAgo: 0, hour: 17, minute: 42,
            merchant: "Sample Cafe",
            description: "Sample purchase · cafe",
            amount: -14.65, category: "RESTAURANTS",
            account: .discoverCC)
        add(daysAgo: 0, hour: 15, minute: 10,
            merchant: "Demo AI Subscription",
            description: "Sample recurring · AI service",
            amount: -20.00, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 0, hour: 12, minute: 30,
            merchant: "Sample BNPL Payment",
            description: "Sample buy-now-pay-later payment",
            amount: -125.78, category: "LOANS",
            account: .advPlusBanking)
        add(daysAgo: 0, hour: 11, minute: 5,
            merchant: "Sample Grocery",
            description: "Sample purchase · grocery",
            amount: -86.42, category: "GROCERIES",
            account: .discoverCC)
        add(daysAgo: 0, hour: 9, minute: 50,
            merchant: "Sample Coffee Shop",
            description: "Sample purchase · coffee shop",
            amount: -6.75, category: "RESTAURANTS",
            account: .discoverCC, pending: true)
        add(daysAgo: 0, hour: 8, minute: 22,
            merchant: "Sample Streaming Service",
            description: "Sample recurring · streaming",
            amount: -22.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)

        // --- Yesterday — 5 rows -----------------------------------------
        add(daysAgo: 1, hour: 20, minute: 4,
            merchant: "Sample Fast Casual",
            description: "Sample purchase · fast casual",
            amount: -16.30, category: "RESTAURANTS",
            account: .discoverCC)
        add(daysAgo: 1, hour: 17, minute: 33,
            merchant: "Sample Online Marketplace",
            description: "Sample order",
            amount: -64.20, category: "SHOPPING",
            account: .platinumVisa)
        add(daysAgo: 1, hour: 14, minute: 12,
            merchant: "Sample BNPL Payment",
            description: "Sample buy-now-pay-later payment",
            amount: -57.40, category: "LOANS",
            account: .advPlusBanking)
        add(daysAgo: 1, hour: 10, minute: 0,
            merchant: "Sample Payroll Deposit",
            description: "Sample ACH credit · employer payroll",
            amount: 3460.82, category: "INCOME",
            account: .advPlusBanking)
        add(daysAgo: 1, hour: 8, minute: 45,
            merchant: "Sample Music Subscription",
            description: "Sample recurring · music streaming",
            amount: -16.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)

        // --- 2 days ago — 4 rows ----------------------------------------
        add(daysAgo: 2, hour: 19, minute: 1,
            merchant: "Sample Rideshare",
            description: "Sample ride · short trip",
            amount: -18.92, category: "TRANSPORT",
            account: .discoverCC)
        add(daysAgo: 2, hour: 15, minute: 28,
            merchant: "Sample Apparel Brand",
            description: "Sample online order",
            amount: -129.50, category: "CLOTHING",
            account: .platinumVisa)
        add(daysAgo: 2, hour: 11, minute: 18,
            merchant: "Sample Specialty Grocer",
            description: "Sample purchase · grocery",
            amount: -42.10, category: "GROCERIES",
            account: .advPlusBanking)
        add(daysAgo: 2, hour: 9, minute: 0,
            merchant: "Demo AI Subscription 2",
            description: "Sample recurring · AI service",
            amount: -20.00, category: "SUBSCRIPTIONS",
            account: .platinumVisa)

        // --- 3 days ago — 4 rows ----------------------------------------
        add(daysAgo: 3, hour: 21, minute: 50,
            merchant: "Sample Cinema",
            description: "Sample purchase · movie tickets",
            amount: -28.40, category: "ENTERTAINMENT",
            account: .discoverCC)
        add(daysAgo: 3, hour: 16, minute: 22,
            merchant: "Sample P2P Transfer",
            description: "Sample peer-to-peer payment",
            amount: -200.00, category: "TRANSFER",
            account: .advPlusBanking)
        add(daysAgo: 3, hour: 12, minute: 10,
            merchant: "Sample Gym Membership",
            description: "Sample recurring · monthly membership",
            amount: -39.99, category: "PERSONAL CARE",
            account: .platinumVisa)
        add(daysAgo: 3, hour: 8, minute: 35,
            merchant: "Sample Burger Place",
            description: "Sample purchase · burger",
            amount: -19.85, category: "RESTAURANTS",
            account: .discoverCC)

        // --- 4 days ago — 4 rows ----------------------------------------
        add(daysAgo: 4, hour: 18, minute: 12,
            merchant: "Sample Installment Loan",
            description: "Sample installment payment",
            amount: -45.00, category: "LOANS",
            account: .advPlusBanking)
        add(daysAgo: 4, hour: 14, minute: 4,
            merchant: "Sample Cloud Storage",
            description: "Sample recurring · cloud storage",
            amount: -9.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 4, hour: 11, minute: 56,
            merchant: "Sample Apparel Brand 2",
            description: "Sample purchase · apparel",
            amount: -76.30, category: "CLOTHING",
            account: .discoverCC)
        add(daysAgo: 4, hour: 8, minute: 0,
            merchant: "Sample Supermarket",
            description: "Sample purchase · grocery",
            amount: -94.18, category: "GROCERIES",
            account: .advPlusBanking)

        // --- 6 days ago — 3 rows ----------------------------------------
        add(daysAgo: 6, hour: 19, minute: 30,
            merchant: "Sample Audio Subscription",
            description: "Sample recurring · audio service",
            amount: -16.99, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 6, hour: 13, minute: 45,
            merchant: "Sample Wallet Cash-Out",
            description: "Sample transfer · wallet to bank",
            amount: 120.00, category: "TRANSFER",
            account: .payPal)
        add(daysAgo: 6, hour: 9, minute: 22,
            merchant: "Sample Hair Salon",
            description: "Sample purchase · haircut",
            amount: -28.00, category: "PERSONAL CARE",
            account: .discoverCC)

        // --- 7 days ago — 4 rows ----------------------------------------
        add(daysAgo: 7, hour: 20, minute: 8,
            merchant: "Sample News Subscription",
            description: "Sample recurring · news + cooking",
            amount: -25.00, category: "SUBSCRIPTIONS",
            account: .platinumVisa)
        add(daysAgo: 7, hour: 15, minute: 4,
            merchant: "Sample Game Store",
            description: "Sample purchase · digital game",
            amount: -29.99, category: "ENTERTAINMENT",
            account: .discoverCC)
        add(daysAgo: 7, hour: 12, minute: 22,
            merchant: "Sample ATM Fee",
            description: "Sample fee · out-of-network ATM",
            amount: -3.50, category: "FEES",
            account: .advPlusBanking)
        add(daysAgo: 7, hour: 10, minute: 30,
            merchant: "Sample Supermarket 2",
            description: "Sample purchase · grocery",
            amount: -58.92, category: "GROCERIES",
            account: .advPlusBanking)

        // --- Already-reviewed rows (so the inbox total isn't the
        // same as the ledger total). These should not appear in
        // sections; they exist so the footer "N of TOTAL" reads
        // realistically and tests can verify the filter.
        add(daysAgo: 8, hour: 12, minute: 0,
            merchant: "Sample Athletic Brand",
            description: "Sample purchase · athletic apparel",
            amount: -84.00, category: "CLOTHING",
            account: .discoverCC,
            reviewed: true)
        add(daysAgo: 9, hour: 12, minute: 0,
            merchant: "Sample Casual Apparel",
            description: "Sample purchase · casual apparel",
            amount: -51.20, category: "CLOTHING",
            account: .platinumVisa,
            reviewed: true)
        add(daysAgo: 9, hour: 9, minute: 0,
            merchant: "Sample Credit Card Payment",
            description: "Sample credit-card payment",
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
