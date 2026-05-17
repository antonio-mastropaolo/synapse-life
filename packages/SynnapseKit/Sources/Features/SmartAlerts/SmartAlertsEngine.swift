import Foundation
import Models

/// Pure-function rules engine. Given a set of installed rules and a
/// data snapshot, return the alerts that fire. Stateless — the host
/// is responsible for deduping fires across runs (we emit one alert
/// per (rule, subject) pair).
public enum SmartAlertsEngine {

    public static func evaluate(rules: [AlertRule], snapshot: AlertsSnapshot) -> [FiredAlert] {
        var fired: [FiredAlert] = []
        for rule in rules where rule.enabled {
            switch rule.kind {
            case .balanceLow(let accountKind, let threshold):
                fired.append(contentsOf: evaluateBalanceLow(
                    rule: rule,
                    kind: accountKind,
                    threshold: threshold,
                    snapshot: snapshot
                ))
            case .newRecurring:
                fired.append(contentsOf: evaluateNewRecurring(rule: rule, snapshot: snapshot))
            case .unusualSpend(let cat, let threshold):
                fired.append(contentsOf: evaluateUnusualSpend(
                    rule: rule,
                    categoryLabel: cat,
                    threshold: threshold,
                    snapshot: snapshot
                ))
            }
        }
        // Sort: alert > warning > info; then most recent first.
        return fired.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return severityRank(lhs.severity) > severityRank(rhs.severity)
            }
            return lhs.firedAt > rhs.firedAt
        }
    }

    /// AI-suggested rules — surfaced as chips the user can accept.
    /// We compute three candidate suggestions from observable signal
    /// and emit only those that aren't already installed.
    public static func suggestRules(snapshot: AlertsSnapshot, existing: [AlertRule]) -> [AlertRule] {
        var suggestions: [AlertRule] = []
        let existingKinds = Set(existing.map { kindKey($0.kind) })

        // 1) Restaurant daily threshold if there's recent dining signal.
        let diningRows = snapshot.transactions.filter { tx in
            guard let a = tx.amount, a < 0, !tx.pending else { return false }
            let label = tx.category.displayLabel.lowercased()
            return label.contains("dining") || label.contains("restaurant") || label.contains("food")
        }
        if let suggested = suggestUnusualSpend(
            categoryLabel: "Restaurants",
            rows: diningRows,
            now: snapshot.now
        ), !existingKinds.contains(kindKey(suggested.kind)) {
            suggestions.append(suggested)
        }

        // 2) Checking balance low if checking has bounced near a floor.
        if let checking = snapshot.accounts.first(where: { $0.kind == .checking }),
           let bal = checking.currentBalance, bal > 0 {
            let tenPercent = bal * (Decimal(string: "0.1") ?? Decimal(0))
            let suggested = AlertRule(
                id: "suggested.balanceLow.checking",
                kind: .balanceLow(accountKind: .checking, threshold: max(500, tenPercent)),
                enabled: false,
                createdAt: snapshot.now,
                isAISuggested: true
            )
            if !existingKinds.contains(kindKey(suggested.kind)) {
                suggestions.append(suggested)
            }
        }

        // 3) New recurring detection — always suggest if not present.
        let newRecurringRule = AlertRule(
            id: "suggested.newRecurring",
            kind: .newRecurring,
            enabled: false,
            createdAt: snapshot.now,
            isAISuggested: true
        )
        if !existingKinds.contains(kindKey(newRecurringRule.kind)) {
            suggestions.append(newRecurringRule)
        }
        return suggestions
    }

    // MARK: - Rule evaluators

    static func evaluateBalanceLow(
        rule: AlertRule,
        kind: AccountKind,
        threshold: Decimal,
        snapshot: AlertsSnapshot
    ) -> [FiredAlert] {
        return snapshot.accounts.compactMap { acct -> FiredAlert? in
            guard acct.kind == kind, let bal = acct.currentBalance, bal < threshold else { return nil }
            return FiredAlert(
                id: "fire.\(rule.id).\(acct.id)",
                ruleId: rule.id,
                firedAt: snapshot.now,
                subjectId: acct.id,
                headline: "\(acct.name) is low",
                body: "Balance \(formatCurrency(bal)) is under your \(formatCurrency(threshold)) threshold.",
                severity: bal < (threshold / 2) ? .alert : .warning
            )
        }
    }

    static func evaluateNewRecurring(rule: AlertRule, snapshot: AlertsSnapshot) -> [FiredAlert] {
        // Use the recurring detector from the Forecast feature. Any
        // detected merchant that isn't in the prior-merchants set is
        // "new".
        let predicted = ForecastReducer.predictedRecurrings(
            transactions: snapshot.transactions,
            today: snapshot.now
        )
        return predicted.compactMap { p -> FiredAlert? in
            let key = p.merchantName.uppercased()
            guard !snapshot.priorMerchants.contains(key) else { return nil }
            return FiredAlert(
                id: "fire.\(rule.id).\(key)",
                ruleId: rule.id,
                firedAt: snapshot.now,
                subjectId: p.id,
                headline: "New recurring: \(p.merchantName)",
                body: "Detected \(formatCurrency(p.amount)) charge cadence — next on \(formatShortDate(p.date)).",
                severity: .info
            )
        }
    }

    static func evaluateUnusualSpend(
        rule: AlertRule,
        categoryLabel: String?,
        threshold: Decimal,
        snapshot: AlertsSnapshot
    ) -> [FiredAlert] {
        let cal = Calendar(identifier: .gregorian)
        // Aggregate today's debits by category.
        var byCategory: [String: (total: Decimal, lastID: String)] = [:]
        let startOfToday = cal.startOfDay(for: snapshot.now)
        for tx in snapshot.transactions {
            guard let a = tx.amount, a < 0, !tx.pending else { continue }
            guard tx.date >= startOfToday, tx.date <= snapshot.now else { continue }
            let key = tx.category.displayLabel
            if let scoped = categoryLabel, key != scoped { continue }
            var bucket = byCategory[key] ?? (.zero, tx.id)
            bucket.total += absDecimal(a)
            bucket.lastID = tx.id
            byCategory[key] = bucket
        }
        return byCategory.compactMap { (key, bucket) -> FiredAlert? in
            guard bucket.total > threshold else { return nil }
            return FiredAlert(
                id: "fire.\(rule.id).\(key)",
                ruleId: rule.id,
                firedAt: snapshot.now,
                subjectId: bucket.lastID,
                headline: "\(key) spend over threshold",
                body: "You've spent \(formatCurrency(bucket.total)) on \(key) today (limit \(formatCurrency(threshold))).",
                severity: .warning
            )
        }
    }

    // MARK: - Suggestion helpers

    static func suggestUnusualSpend(
        categoryLabel: String,
        rows: [Transaction],
        now: Date
    ) -> AlertRule? {
        guard rows.count >= 5 else { return nil }
        // Daily mean over the last 30 days.
        let cal = Calendar(identifier: .gregorian)
        let cutoff = cal.startOfDay(for: now).addingTimeInterval(-30 * 24 * 3600)
        var byDay: [Date: Decimal] = [:]
        for tx in rows where tx.date >= cutoff {
            let day = cal.startOfDay(for: tx.date)
            byDay[day, default: 0] += absDecimal(tx.amount ?? 0)
        }
        guard !byDay.isEmpty else { return nil }
        let total = byDay.values.reduce(Decimal.zero, +)
        let mean = total / Decimal(byDay.count)
        // Threshold = 2× daily mean, rounded to nearest $5.
        let raw = mean * Decimal(2)
        let rounded = roundToNearest(raw, step: 5)
        guard rounded >= 20 else { return nil }
        return AlertRule(
            id: "suggested.unusualSpend.\(categoryLabel)",
            kind: .unusualSpend(categoryLabel: categoryLabel, dailyThreshold: rounded),
            enabled: false,
            createdAt: now,
            isAISuggested: true
        )
    }

    static func kindKey(_ kind: AlertRule.Kind) -> String {
        switch kind {
        case .balanceLow(let k, _): return "balanceLow.\(k.rawValue)"
        case .newRecurring: return "newRecurring"
        case .unusualSpend(let label, _): return "unusualSpend.\(label ?? "_any")"
        }
    }

    static func severityRank(_ s: FiredAlert.Severity) -> Int {
        switch s {
        case .alert: return 3
        case .warning: return 2
        case .info: return 1
        }
    }

    static func roundToNearest(_ value: Decimal, step: Int) -> Decimal {
        let d = NSDecimalNumber(decimal: value).doubleValue
        let stepD = Double(step)
        let rounded = (d / stepD).rounded() * stepD
        return Decimal(rounded)
    }
}
