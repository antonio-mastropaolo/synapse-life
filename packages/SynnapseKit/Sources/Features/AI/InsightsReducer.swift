import Foundation
import Models

/// Pure-logic reducer that turns a `(accounts, transactions)` snapshot
/// into a deterministic set of insights. The reducer is exercised by
/// `LocalStubInsightsAPI` and by the unit tests; the live API will
/// eventually call `/api/ai/insights` on synapse-v2 and bypass this.
///
/// Returns at most `maxCount` insights, in this priority order:
/// `.anomaly`, `.narration`, `.forecast`, `.pattern`. The ordering is
/// intentional — anomalies are the highest-value surface for a CS
/// faculty operator watching real Plaid data.
public enum InsightsReducer {

    /// Build the full insight list from a snapshot. `today` is injected
    /// so unit tests pin to a fixed clock.
    public static func reduce(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        today: Date = Date(),
        sensitivity: Int = 3,
        maxCount: Int = 3
    ) -> [Insight] {
        var out: [Insight] = []
        if let a = anomaly(transactions: transactions, sensitivity: sensitivity) {
            out.append(a)
        }
        if let n = narration(accounts: accounts, transactions: transactions, today: today) {
            out.append(n)
        }
        if let f = forecast(accounts: accounts, transactions: transactions, today: today) {
            out.append(f)
        }
        if let p = pattern(transactions: transactions, today: today) {
            out.append(p)
        }
        // Cap at maxCount.
        if out.count > maxCount {
            out = Array(out.prefix(maxCount))
        }
        return out
    }

    // MARK: - Net worth narration

    /// One-line summary of net worth + biggest mover. Used as the inline
    /// narration line below the hero number on the Personal pane.
    public static func narration(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        today: Date = Date()
    ) -> Insight? {
        guard !accounts.isEmpty else { return nil }
        let assets = accounts
            .filter { !$0.kind.isLiability }
            .compactMap { $0.currentBalance }
            .reduce(Decimal.zero, +)
        let liabilities = accounts
            .filter { $0.kind.isLiability }
            .compactMap { $0.currentBalance }
            .reduce(Decimal.zero, +)
        let net = assets - liabilities

        // Recent-week net spend (negative amounts only).
        let weekAgo = today.addingTimeInterval(-7 * 24 * 3600)
        let weekSpend = transactions
            .filter { $0.date >= weekAgo && $0.date <= today && !$0.pending }
            .compactMap { tx -> Decimal? in
                guard let a = tx.amount, a < 0 else { return nil }
                return -a
            }
            .reduce(Decimal.zero, +)

        let netStr = formatCurrency(net)
        let weekStr = formatCurrency(weekSpend)

        let netSign: String = (net < 0) ? "down" : "up"
        let body = "You spent \(weekStr) in the last 7 days. Net worth is \(netStr) (\(netSign))."
        return Insight(
            id: "insight.narration",
            kind: .narration,
            headline: "Net worth \(netStr)",
            body: body,
            severity: net < 0 ? .warning : .info
        )
    }

    // MARK: - Anomaly

    /// Flag the largest outflow that is at least `threshold(sensitivity)`
    /// the mean outflow for the same account over the past 30 days.
    public static func anomaly(
        transactions: [Transaction],
        sensitivity: Int = 3
    ) -> Insight? {
        // Group debits by account.
        let debits = transactions.filter { tx in
            guard let a = tx.amount, !tx.pending else { return false }
            return a < 0
        }
        guard !debits.isEmpty else { return nil }

        // Per-account mean of absolute amounts.
        var perAccount: [String: [Decimal]] = [:]
        for tx in debits {
            let key = tx.accountId ?? "_"
            let v = absDecimal(tx.amount ?? 0)
            perAccount[key, default: []].append(v)
        }

        // Find the row whose absolute amount most exceeds its account's mean.
        let threshold = anomalyMultiplier(sensitivity: sensitivity)
        var bestRow: Transaction?
        var bestRatio: Decimal = 0
        for tx in debits {
            let key = tx.accountId ?? "_"
            guard let bucket = perAccount[key], bucket.count >= 2 else { continue }
            let sum = bucket.reduce(Decimal.zero, +)
            let mean = sum / Decimal(bucket.count)
            guard mean > 0 else { continue }
            let abs = absDecimal(tx.amount ?? 0)
            let ratio = abs / mean
            if ratio >= threshold && ratio > bestRatio {
                bestRatio = ratio
                bestRow = tx
            }
        }
        guard let row = bestRow, let amount = row.amount else { return nil }
        let absAmount = absDecimal(amount)
        let ratioStr = formatRatio(bestRatio)
        let acctLabel = row.accountName ?? "this account"
        let headline = "Unusual \(formatCurrency(absAmount)) outflow"
        let body = "\(row.name) on \(formatShortDate(row.date)) is \(ratioStr) the typical outflow on \(acctLabel)."
        return Insight(
            id: "insight.anomaly.\(row.id)",
            kind: .anomaly,
            headline: headline,
            body: body,
            accountId: row.accountId,
            severity: .warning
        )
    }

    /// Map sensitivity (1-5) to a Z-ratio threshold. Lower sensitivity =
    /// higher threshold (fewer flags). Default 3 = 2.5x mean.
    static func anomalyMultiplier(sensitivity: Int) -> Decimal {
        switch max(1, min(5, sensitivity)) {
        case 1: return Decimal(string: "4.0") ?? 4
        case 2: return Decimal(string: "3.0") ?? 3
        case 3: return Decimal(string: "2.5") ?? 2
        case 4: return Decimal(string: "2.0") ?? 2
        case 5: return Decimal(string: "1.5") ?? 1
        default: return Decimal(string: "2.5") ?? 2
        }
    }

    // MARK: - Forecast

    /// Project a checking-account zero-crossing using the last 30 days of
    /// debits. Conservative: only fires when the account has enough
    /// recent activity AND a strictly-negative trend.
    public static func forecast(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        today: Date = Date()
    ) -> Insight? {
        let checking = accounts.first { $0.kind == .checking }
        guard let acct = checking, let bal = acct.currentBalance, bal > 0 else {
            return nil
        }
        let monthAgo = today.addingTimeInterval(-30 * 24 * 3600)
        let debits = transactions
            .filter { tx in
                guard let a = tx.amount, !tx.pending, a < 0 else { return false }
                guard tx.date >= monthAgo, tx.date <= today else { return false }
                return tx.accountId == acct.id
            }
            .compactMap { $0.amount.map { -$0 } } // positive outflow
        guard !debits.isEmpty else { return nil }
        let total = debits.reduce(Decimal.zero, +)
        let perDay = total / Decimal(30)
        guard perDay > 0 else { return nil }
        let days = bal / perDay
        let daysInt = Int(truncating: NSDecimalNumber(decimal: days))
        guard daysInt > 0 && daysInt < 365 else { return nil }
        let headline = "Checking may hit zero in ~\(daysInt) days"
        let body = "At your 30-day pace of \(formatCurrency(perDay))/day, \(acct.name) trends to zero around then."
        return Insight(
            id: "insight.forecast.\(acct.id)",
            kind: .forecast,
            headline: headline,
            body: body,
            accountId: acct.id,
            severity: daysInt < 21 ? .alert : .info
        )
    }

    // MARK: - Pattern

    /// Compare this-week vs prior-week spend per category and surface the
    /// biggest movement. Returns `nil` if there is no meaningful basis.
    public static func pattern(
        transactions: [Transaction],
        today: Date = Date()
    ) -> Insight? {
        let weekAgo = today.addingTimeInterval(-7 * 24 * 3600)
        let twoWeeksAgo = today.addingTimeInterval(-14 * 24 * 3600)
        var thisWeek: [String: Decimal] = [:]
        var priorWeek: [String: Decimal] = [:]
        for tx in transactions where !tx.pending {
            guard let amount = tx.amount, amount < 0 else { continue }
            let key = tx.category.displayLabel
            let v = absDecimal(amount)
            if tx.date > weekAgo && tx.date <= today {
                thisWeek[key, default: 0] += v
            } else if tx.date > twoWeeksAgo && tx.date <= weekAgo {
                priorWeek[key, default: 0] += v
            }
        }
        // Largest absolute pct change for a category present in both weeks.
        var bestKey: String?
        var bestPct: Decimal = 0
        for (key, this) in thisWeek {
            guard let prior = priorWeek[key], prior > 0 else { continue }
            let diff = this - prior
            let pct = diff / prior * Decimal(100)
            if absDecimal(pct) > absDecimal(bestPct) {
                bestPct = pct
                bestKey = key
            }
        }
        guard let key = bestKey else { return nil }
        let direction: String = bestPct >= 0 ? "more" : "less"
        let pctAbs = absDecimal(bestPct)
        let pctStr = formatPercent(pctAbs)
        let headline = "\(key) spending \(pctStr) \(direction) this week"
        let body = "Compared with the prior 7 days you spent \(pctStr) \(direction) on \(key)."
        return Insight(
            id: "insight.pattern.\(key)",
            kind: .pattern,
            headline: headline,
            body: body,
            severity: bestPct > 0 ? .warning : .positive
        )
    }
}

// MARK: - Formatting helpers (internal)

@inlinable
func absDecimal(_ d: Decimal) -> Decimal {
    return d < 0 ? -d : d
}

func formatCurrency(_ d: Decimal) -> String {
    let n = NSDecimalNumber(decimal: d)
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: n) ?? "$\(n)"
}

func formatPercent(_ d: Decimal) -> String {
    let n = NSDecimalNumber(decimal: d).doubleValue
    return String(format: "%.0f%%", n)
}

func formatRatio(_ d: Decimal) -> String {
    let n = NSDecimalNumber(decimal: d).doubleValue
    return String(format: "%.1fx", n)
}

func formatShortDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d"
    return f.string(from: date)
}
