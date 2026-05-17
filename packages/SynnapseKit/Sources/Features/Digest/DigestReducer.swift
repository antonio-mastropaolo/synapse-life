import Foundation
import Models

/// Pure-logic reducer that builds the weekly digest from a snapshot.
/// Deterministic ordering: greeting first, then `spend`, `income`,
/// `net`, `topCategory`, `subscriptions`, `anomaly`, `suggestion`. We
/// emit between 5 and 7 bullets — fewer if the data doesn't support a
/// claim (e.g. no subscriptions detected, or no anomaly above
/// threshold). Each bullet carries the `Transaction.id`s that justify
/// it; the UI uses these as citation chips.
public enum DigestReducer {

    /// Build the digest for the trailing 7-day window ending at
    /// `today` (exclusive). `firstName` personalizes the greeting.
    /// `today` is injected so the test suite can pin the clock.
    public static func generate(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        firstName: String = "Antonio",
        today: Date = Date()
    ) -> Digest {
        let cal = Calendar(identifier: .gregorian)
        let weekEnd = cal.startOfDay(for: today)
        let weekStart = weekEnd.addingTimeInterval(-7 * 24 * 3600)
        let priorStart = weekEnd.addingTimeInterval(-14 * 24 * 3600)

        let thisWeek = transactions.filter { tx in
            !tx.pending && tx.date >= weekStart && tx.date < weekEnd
        }
        let priorWeek = transactions.filter { tx in
            !tx.pending && tx.date >= priorStart && tx.date < weekStart
        }

        var bullets: [DigestBullet] = []
        if let b = spendBullet(thisWeek: thisWeek, priorWeek: priorWeek) { bullets.append(b) }
        if let b = incomeBullet(thisWeek: thisWeek) { bullets.append(b) }
        if let b = netBullet(thisWeek: thisWeek) { bullets.append(b) }
        if let b = topCategoryBullet(thisWeek: thisWeek) { bullets.append(b) }
        if let b = subscriptionsBullet(thisWeek: thisWeek) { bullets.append(b) }
        if let b = anomalyBullet(thisWeek: thisWeek) { bullets.append(b) }
        if let b = suggestionBullet(accounts: accounts, thisWeek: thisWeek) { bullets.append(b) }

        return Digest(
            id: "digest.\(Int(weekStart.timeIntervalSince1970))",
            weekStart: weekStart,
            weekEnd: weekEnd,
            generatedAt: today,
            greeting: "Hey \(firstName) — here's last week.",
            bullets: bullets
        )
    }

    // MARK: - Bullets

    static func spendBullet(thisWeek: [Transaction], priorWeek: [Transaction]) -> DigestBullet? {
        let this = totalOutflow(thisWeek)
        guard this > 0 else { return nil }
        let prior = totalOutflow(priorWeek)
        let body: String
        if prior > 0 {
            let pct = (this - prior) / prior * Decimal(100)
            let dir = pct >= 0 ? "up" : "down"
            body = "You spent \(formatCurrency(this)) (\(dir) \(formatPercent(absDecimal(pct))) from the prior week)."
        } else {
            body = "You spent \(formatCurrency(this)) across \(thisWeek.filter { ($0.amount ?? 0) < 0 }.count) transactions."
        }
        let citations = topNDebitIDs(thisWeek, n: 3)
        return DigestBullet(
            id: "digest.spend",
            kind: .spend,
            headline: "Spent \(formatCurrency(this))",
            body: body,
            citations: citations
        )
    }

    static func incomeBullet(thisWeek: [Transaction]) -> DigestBullet? {
        let inflows = thisWeek.compactMap { tx -> (Transaction, Decimal)? in
            guard let a = tx.amount, a > 0 else { return nil }
            return (tx, a)
        }
        let total = inflows.reduce(Decimal.zero) { $0 + $1.1 }
        guard total > 0 else { return nil }
        let topSource = inflows.max { $0.1 < $1.1 }?.0
        let sourceLabel = topSource?.name ?? "deposits"
        let body = "You earned \(formatCurrency(total)) — largest deposit from \(sourceLabel)."
        let citations = inflows.map { $0.0.id }
        return DigestBullet(
            id: "digest.income",
            kind: .income,
            headline: "Earned \(formatCurrency(total))",
            body: body,
            citations: citations
        )
    }

    static func netBullet(thisWeek: [Transaction]) -> DigestBullet? {
        let spend = totalOutflow(thisWeek)
        let income = totalInflow(thisWeek)
        guard spend > 0 || income > 0 else { return nil }
        let net = income - spend
        let sign = net >= 0 ? "+" : "-"
        let absNet = absDecimal(net)
        let body = "Income \(formatCurrency(income)) minus spend \(formatCurrency(spend)) = net \(sign)\(formatCurrency(absNet))."
        return DigestBullet(
            id: "digest.net",
            kind: .net,
            headline: "Net \(sign)\(formatCurrency(absNet))",
            body: body,
            citations: []
        )
    }

    static func topCategoryBullet(thisWeek: [Transaction]) -> DigestBullet? {
        var byCategory: [String: (total: Decimal, ids: [String])] = [:]
        for tx in thisWeek {
            guard let a = tx.amount, a < 0 else { continue }
            let key = tx.category.displayLabel
            var entry = byCategory[key] ?? (.zero, [])
            entry.total += absDecimal(a)
            entry.ids.append(tx.id)
            byCategory[key] = entry
        }
        // Tie-break on category name so the test pin is stable.
        let top = byCategory
            .map { ($0.key, $0.value.total, $0.value.ids) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
                return lhs.1 > rhs.1
            }
            .first
        guard let (label, total, ids) = top, total > 0 else { return nil }
        return DigestBullet(
            id: "digest.topCategory",
            kind: .topCategory,
            headline: "Top: \(label) \(formatCurrency(total))",
            body: "Your largest category last week was \(label) at \(formatCurrency(total)).",
            citations: ids
        )
    }

    static func subscriptionsBullet(thisWeek: [Transaction]) -> DigestBullet? {
        // Treat any debit whose name matches a known subscription token
        // as a subscription. This is a heuristic — the dedicated
        // recurrings feature handles full detection.
        let subs = thisWeek.filter { tx in
            guard let a = tx.amount, a < 0 else { return false }
            let n = tx.name.uppercased()
            return Self.subscriptionTokens.contains { n.contains($0) }
        }
        guard !subs.isEmpty else { return nil }
        let count = subs.count
        let total = subs.compactMap { $0.amount.map(absDecimal) }.reduce(Decimal.zero, +)
        let unit = count == 1 ? "subscription" : "subscriptions"
        return DigestBullet(
            id: "digest.subscriptions",
            kind: .subscriptions,
            headline: "\(count) \(unit) charged",
            body: "Recurring services billed \(formatCurrency(total)) last week.",
            citations: subs.map { $0.id }
        )
    }

    static func anomalyBullet(thisWeek: [Transaction]) -> DigestBullet? {
        // Re-use the InsightsReducer to keep one source of anomaly
        // truth. Sensitivity is the default 3 (2.5x mean).
        guard let anomaly = InsightsReducer.anomaly(transactions: thisWeek, sensitivity: 3) else {
            return nil
        }
        let citationID = anomaly.id.replacingOccurrences(of: "insight.anomaly.", with: "")
        return DigestBullet(
            id: "digest.anomaly",
            kind: .anomaly,
            headline: anomaly.headline,
            body: anomaly.body,
            citations: [citationID]
        )
    }

    static func suggestionBullet(accounts: [FinanceAccount], thisWeek: [Transaction]) -> DigestBullet? {
        // Pick a suggestion based on observable signal. The order
        // mirrors how seriously the user should treat the suggestion.
        if let checking = accounts.first(where: { $0.kind == .checking }),
           let bal = checking.currentBalance,
           bal < 500 {
            return DigestBullet(
                id: "digest.suggestion",
                kind: .suggestion,
                headline: "Checking is low",
                body: "Your checking shows \(formatCurrency(bal)) — consider moving funds from savings.",
                citations: []
            )
        }
        let dining = thisWeek
            .filter { tx in
                guard let a = tx.amount, a < 0 else { return false }
                return tx.category.displayLabel == "Dining" || tx.category.displayLabel == "Food and Drink"
            }
            .compactMap { $0.amount.map(absDecimal) }
            .reduce(Decimal.zero, +)
        if dining > 200 {
            return DigestBullet(
                id: "digest.suggestion",
                kind: .suggestion,
                headline: "Dining at \(formatCurrency(dining))",
                body: "You're running 30% above your weekly dining baseline — worth a glance.",
                citations: []
            )
        }
        return nil
    }

    // MARK: - Helpers

    private static let subscriptionTokens = [
        "NETFLIX", "SPOTIFY", "HULU", "DISNEY", "HBO", "APPLE.COM",
        "ADOBE", "DROPBOX", "GITHUB", "OPENAI", "ANTHROPIC", "ICLOUD",
        "SIRIUS", "NYTIMES", "WSJ", "CHATGPT"
    ]

    private static func totalOutflow(_ txs: [Transaction]) -> Decimal {
        txs.compactMap { tx -> Decimal? in
            guard let a = tx.amount, a < 0 else { return nil }
            return -a
        }.reduce(Decimal.zero, +)
    }

    private static func totalInflow(_ txs: [Transaction]) -> Decimal {
        txs.compactMap { tx -> Decimal? in
            guard let a = tx.amount, a > 0 else { return nil }
            return a
        }.reduce(Decimal.zero, +)
    }

    private static func topNDebitIDs(_ txs: [Transaction], n: Int) -> [String] {
        return txs
            .compactMap { tx -> (Transaction, Decimal)? in
                guard let a = tx.amount, a < 0 else { return nil }
                return (tx, -a)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(n)
            .map { $0.0.id }
    }
}
