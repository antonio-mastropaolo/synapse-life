import Foundation
import Models
import Networking
import Features

/// Demo fixtures used to seed the Mock APIs when the app boots in DEBUG.
///
/// The login gate was removed: Synnapse boots directly into the cockpit
/// shell. Live API calls against `localhost:3000` would either fail
/// silently or render empty states, neither of which is the experience
/// we want when the user just launches the app. In DEBUG we swap Live →
/// Mock and pre-seed the mocks with representative private-life data so
/// Finance / Life / Advisors render something on first paint.
///
/// Release builds still inject the Live APIs and talk to the real
/// `synapse-v2` server, so this module never participates in shipping
/// binaries that target the server contract.
@MainActor
public enum DemoData {

    /// Pre-seed the given mocks with deterministic private-life data.
    /// Idempotent: calling twice just overwrites the queued state on
    /// each mock actor.
    public static func seed(
        finance: MockFinanceAPI,
        life: MockLifeAPI,
        advisors: MockAdvisorsAPI
    ) async {
        await finance.setAccounts(financeAccounts(), etag: "demo-accounts-v1")
        await finance.setTransactions(transactions())
        await finance.setInvestments(investments())
        await life.setEntries(lifeEntries())
        await advisors.setListResponse(advisorPersonas())
    }

    // MARK: - Finance fixtures

    private static func financeAccounts() -> [FinanceAccount] {
        let capturedAt = Date(timeIntervalSince1970: 1_715_000_000)
        return [
            FinanceAccount(
                id: "acc-checking-01",
                institutionId: "ins_chase",
                institutionName: "Chase",
                name: "Everyday Checking",
                officialName: "Chase Total Checking",
                mask: "4421",
                kind: .checking,
                currency: "USD",
                // Deliberately low so the BalanceProjector's
                // zero-crossing banner fires once the upcoming rent
                // hit is applied. Savings still carries the real
                // runway; this is the day-to-day account. With
                // bi-weekly payroll landing ahead of the apartment
                // debit, the balance has to be small enough that
                // the rent overshoots even after the payroll lift.
                currentBalance: Decimal(string: "212.55"),
                availableBalance: Decimal(string: "112.55"),
                limitAmount: nil,
                balanceCapturedAt: capturedAt
            ),
            FinanceAccount(
                id: "acc-savings-01",
                institutionId: "ins_ally",
                institutionName: "Ally Bank",
                name: "High-Yield Savings",
                officialName: "Ally Online Savings",
                mask: "9087",
                kind: .savings,
                currency: "USD",
                currentBalance: Decimal(string: "42180.10"),
                availableBalance: Decimal(string: "42180.10"),
                limitAmount: nil,
                balanceCapturedAt: capturedAt
            ),
            FinanceAccount(
                id: "acc-credit-01",
                institutionId: "ins_amex",
                institutionName: "American Express",
                name: "Gold Card",
                officialName: "American Express Gold",
                mask: "1003",
                kind: .credit,
                currency: "USD",
                currentBalance: Decimal(string: "1284.92"),
                availableBalance: Decimal(string: "23715.08"),
                limitAmount: Decimal(string: "25000.00"),
                balanceCapturedAt: capturedAt
            ),
            FinanceAccount(
                id: "acc-brokerage-01",
                institutionId: "ins_fidelity",
                institutionName: "Fidelity",
                name: "Individual Brokerage",
                officialName: "Fidelity Brokerage Account",
                mask: "5512",
                kind: .brokerage,
                currency: "USD",
                currentBalance: Decimal(string: "184550.22"),
                availableBalance: Decimal(string: "1200.00"),
                limitAmount: nil,
                balanceCapturedAt: capturedAt
            ),
            FinanceAccount(
                id: "acc-retirement-01",
                institutionId: "ins_fidelity",
                institutionName: "Fidelity",
                name: "Roth IRA",
                officialName: "Fidelity Roth IRA",
                mask: "7720",
                kind: .retirement,
                currency: "USD",
                currentBalance: Decimal(string: "67910.40"),
                availableBalance: nil,
                limitAmount: nil,
                balanceCapturedAt: capturedAt
            )
        ]
    }

    private static func transactions() -> [Transaction] {
        // Anchor the synthetic history to "today" (relative to wall
        // clock) rather than a frozen epoch so the detectors fire on
        // a 180-day window the user is actually inside of. The
        // Recurrings + Subscriptions surfaces need ≥ 3 occurrences in
        // the trailing 180-day window to detect a merchant; six
        // months of monthly subs satisfies that with comfortable
        // headroom.
        let now = Date()
        let day: TimeInterval = 86_400
        func d(_ daysAgo: Int) -> Date { now.addingTimeInterval(-day * Double(daysAgo)) }

        var out: [Transaction] = []

        // Recurring SaaS / streaming subs — 6 monthly hits each so
        // SubscriptionDetector picks all three with high confidence.
        let monthlyRecurrings: [(merchant: String, name: String, cat: String, amount: String, accountId: String, accountName: String, dayOfMonth: Int)] = [
            ("Anthropic", "Anthropic — Claude Pro",   "Software",      "-20.00",  "acc-credit-01",   "Gold Card",        15),
            ("Netflix",   "Netflix Premium",          "Subscriptions", "-22.99",  "acc-credit-01",   "Gold Card",        8),
            ("Spotify",   "Spotify Premium Family",   "Subscriptions", "-16.99",  "acc-credit-01",   "Gold Card",        14),
            ("Apple",     "iCloud+ 2TB",              "Subscriptions", "-9.99",   "acc-credit-01",   "Gold Card",        11),
            ("NYTimes",   "NYT Cooking + News",       "Subscriptions", "-25.00",  "acc-credit-01",   "Gold Card",        9),
            ("SiriusXM",  "SiriusXM",                 "Subscriptions", "-16.99",  "acc-credit-01",   "Gold Card",        6),
        ]
        for sub in monthlyRecurrings {
            for i in 0..<6 {
                let daysAgo = sub.dayOfMonth + i * 30
                out.append(Transaction(
                    id: "tx-sub-\(sub.merchant.lowercased())-\(i)",
                    accountId: sub.accountId,
                    accountName: sub.accountName,
                    amount: Decimal(string: sub.amount),
                    currency: "USD",
                    date: d(daysAgo),
                    name: sub.name,
                    merchantName: sub.merchant,
                    category: .knownCategory(sub.cat),
                    subcategory: nil,
                    pending: false
                ))
            }
        }

        // Bi-weekly payroll — drives the income side of the balance
        // projection so the zero-crossing banner reads against a
        // realistic income offset.
        for i in 0..<13 {
            let daysAgo = 2 + i * 14
            out.append(Transaction(
                id: "tx-payroll-\(i)",
                accountId: "acc-checking-01",
                accountName: "Everyday Checking",
                amount: Decimal(string: "3460.82"),
                currency: "USD",
                date: d(daysAgo),
                name: "ACH CREDIT — Payroll",
                merchantName: nil,
                category: .knownCategory("Income"),
                subcategory: "Payroll",
                pending: false
            ))
        }

        // Monthly rent — large debit. Anchor the last occurrence
        // 27 days ago so the next predicted rent lands ~3 days from
        // "now", AHEAD of the next bi-weekly payroll. With checking
        // intentionally low (see `financeAccounts()`), this is the
        // hit that forces the BalanceProjector's zero-crossing
        // banner to fire on the Forecast surface.
        for i in 0..<6 {
            let daysAgo = 27 + i * 30
            out.append(Transaction(
                id: "tx-rent-\(i)",
                accountId: "acc-checking-01",
                accountName: "Everyday Checking",
                amount: Decimal(string: "-1850.00"),
                currency: "USD",
                date: d(daysAgo),
                name: "Rent — Apartment",
                merchantName: "Apartment",
                category: .knownCategory("Housing"),
                subcategory: "Rent",
                pending: false
            ))
        }

        // Hand-picked one-offs so the recent transactions list shows
        // non-recurring rows alongside the predictable spine.
        out.append(contentsOf: [
            Transaction(
                id: "tx-001",
                accountId: "acc-checking-01",
                accountName: "Everyday Checking",
                amount: Decimal(string: "-62.40"),
                currency: "USD",
                date: d(0),
                name: "Whole Foods Market",
                merchantName: "Whole Foods",
                category: .knownCategory("Groceries"),
                subcategory: nil,
                pending: false
            ),
            Transaction(
                id: "tx-002",
                accountId: "acc-credit-01",
                accountName: "Gold Card",
                amount: Decimal(string: "-118.20"),
                currency: "USD",
                date: d(1),
                name: "Delta Airlines",
                merchantName: "Delta",
                category: .knownCategory("Travel"),
                subcategory: "Airlines",
                pending: false
            ),
            Transaction(
                id: "tx-003",
                accountId: "acc-credit-01",
                accountName: "Gold Card",
                amount: Decimal(string: "-14.95"),
                currency: "USD",
                date: d(1),
                name: "Anthropic — Claude Pro",
                merchantName: "Anthropic",
                category: .knownCategory("Software"),
                subcategory: nil,
                pending: false
            ),
            Transaction(
                id: "tx-004",
                accountId: "acc-checking-01",
                accountName: "Everyday Checking",
                amount: Decimal(string: "3850.00"),
                currency: "USD",
                date: d(3),
                name: "Direct Deposit — Payroll",
                merchantName: nil,
                category: .knownCategory("Income"),
                subcategory: "Payroll",
                pending: false
            ),
            Transaction(
                id: "tx-005",
                accountId: "acc-credit-01",
                accountName: "Gold Card",
                amount: Decimal(string: "-46.18"),
                currency: "USD",
                date: d(4),
                name: "Uber",
                merchantName: "Uber",
                category: .knownCategory("Transport"),
                subcategory: nil,
                pending: false
            ),
            Transaction(
                id: "tx-006",
                accountId: "acc-checking-01",
                accountName: "Everyday Checking",
                amount: Decimal(string: "-1850.00"),
                currency: "USD",
                date: d(5),
                name: "Rent — May",
                merchantName: nil,
                category: .knownCategory("Housing"),
                subcategory: "Rent",
                pending: false
            ),
            Transaction(
                id: "tx-007",
                accountId: "acc-credit-01",
                accountName: "Gold Card",
                amount: Decimal(string: "-72.10"),
                currency: "USD",
                date: d(6),
                name: "Trader Joe's",
                merchantName: "Trader Joe's",
                category: .knownCategory("Groceries"),
                subcategory: nil,
                pending: false
            ),
            Transaction(
                id: "tx-008",
                accountId: "acc-savings-01",
                accountName: "High-Yield Savings",
                amount: Decimal(string: "215.40"),
                currency: "USD",
                date: d(7),
                name: "Interest Payment",
                merchantName: nil,
                category: .knownCategory("Income"),
                subcategory: "Interest",
                pending: false
            )
        ])

        // Lower the checking balance so the projected zero-crossing
        // banner reads against meaningful upcoming bills. The seeded
        // accounts will be patched below to a runway closer to the
        // bills hitting in the next 30 days.
        return out
    }

    private static func investments() -> [InvestmentPosition] {
        func pos(
            _ ticker: String,
            _ name: String,
            qty: String,
            px: String,
            cost: String,
            kind: SecurityKind = .stock,
            account: String = "Individual Brokerage",
            accountId: String = "acc-brokerage-01"
        ) -> InvestmentPosition {
            let q = Decimal(string: qty) ?? 0
            let p = Decimal(string: px) ?? 0
            let cb = Decimal(string: cost) ?? 0
            let value = q * p
            let pnl = value - cb
            let pnlPct: Decimal? = cb == 0 ? nil : (pnl / cb) * 100
            return InvestmentPosition(
                securityId: "sec-\(ticker.lowercased())",
                accountId: accountId,
                accountName: account,
                ticker: ticker,
                name: name,
                kind: kind,
                quantity: q,
                price: p,
                value: value,
                costBasis: cb,
                unrealizedPnL: pnl,
                unrealizedPnLPct: pnlPct,
                currency: "USD"
            )
        }
        return [
            pos("AAPL",  "Apple Inc.",      qty: "120",   px: "187.34", cost: "16800.00"),
            pos("MSFT",  "Microsoft",       qty: "85",    px: "402.21", cost: "27000.00"),
            pos("VTI",   "Vanguard Total Market ETF", qty: "210", px: "243.10", cost: "44200.00", kind: .etf),
            pos("NVDA",  "NVIDIA",          qty: "30",    px: "921.05", cost: "9800.00"),
            pos(
                "VTI",   "Vanguard Total Market ETF",
                qty: "55", px: "243.10", cost: "11200.00",
                kind: .etf,
                account: "Roth IRA",
                accountId: "acc-retirement-01"
            ),
            pos(
                "VXUS",  "Vanguard Total International ETF",
                qty: "120", px: "63.84", cost: "7100.00",
                kind: .etf,
                account: "Roth IRA",
                accountId: "acc-retirement-01"
            )
        ]
    }

    // MARK: - Life fixtures

    private static func lifeEntries() -> [LifeEntry] {
        let now = Date(timeIntervalSince1970: 1_715_000_000)
        let hour: TimeInterval = 3600
        func t(_ hoursAgo: Double) -> Date { now.addingTimeInterval(-hour * hoursAgo) }
        return [
            LifeEntry(
                id: "life-boot",
                timestamp: t(8),
                kind: .boot,
                text: "synnapse cockpit online — demo data mode"
            ),
            LifeEntry(
                id: "life-streak",
                timestamp: t(7.5),
                kind: .streak,
                text: "no-spend streak: 3 days · groceries category"
            ),
            LifeEntry(
                id: "life-bill",
                timestamp: t(6),
                kind: .bill,
                text: "rent due in 6 days · $1,850.00"
            ),
            LifeEntry(
                id: "life-txn-1",
                timestamp: t(4),
                kind: .transaction,
                text: "Whole Foods · -$62.40 · groceries"
            ),
            LifeEntry(
                id: "life-insight",
                timestamp: t(2.5),
                kind: .insight,
                text: "software spend up 18% MoM — Anthropic + Linear renewed"
            ),
            LifeEntry(
                id: "life-digest",
                timestamp: t(1),
                kind: .digest,
                text: "weekly digest ready · open Advisors → Wealth Coach"
            )
        ]
    }

    // MARK: - Advisors fixtures

    private static func advisorPersonas() -> [Advisor] {
        let now = Date()
        return [
            Advisor(
                id: "wealth-coach",
                name: "Wealth Coach",
                specialty: "Budgets & cash flow",
                avatarColorHex: "#34d399",
                avatarInitials: "WC",
                unreadCount: 2,
                lastThreadId: nil,
                lastSummary: "Reviewed sub renewals · flagged 3 to cancel",
                lastActiveAt: now.addingTimeInterval(-3_600 * 5)
            ),
            Advisor(
                id: "portfolio-strategist",
                name: "Portfolio Strategist",
                specialty: "Asset allocation",
                avatarColorHex: "#60a5fa",
                avatarInitials: "PS",
                unreadCount: 0,
                lastThreadId: nil,
                lastSummary: "VTI overweight vs target by 4%",
                lastActiveAt: now.addingTimeInterval(-3_600 * 26)
            ),
            Advisor(
                id: "tax-advisor",
                name: "Tax Advisor",
                specialty: "W-2 + 1099 planning",
                avatarColorHex: "#f59e0b",
                avatarInitials: "TA",
                unreadCount: 1,
                lastThreadId: nil,
                lastSummary: "Q2 estimated payment window opens June 1",
                lastActiveAt: now.addingTimeInterval(-3_600 * 12)
            ),
            Advisor(
                id: "career-mentor",
                name: "Career Mentor",
                specialty: "Comp & runway",
                avatarColorHex: "#a78bfa",
                avatarInitials: "CM",
                unreadCount: 0,
                lastThreadId: nil,
                lastSummary: "Runway at 14 months at current burn",
                lastActiveAt: now.addingTimeInterval(-3_600 * 48)
            )
        ]
    }
}
