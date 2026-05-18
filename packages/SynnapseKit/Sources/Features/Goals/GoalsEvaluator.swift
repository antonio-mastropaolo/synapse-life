import Foundation
import Models

/// Pure-function evaluation of a goal against a window of
/// transactions. Mirrors `SmartAlertsEngine.evaluate` — no state, no
/// I/O, trivially testable. The store calls this once per due goal
/// during foreground evaluation and uses the result to roll the
/// goal's deadline forward.
public enum GoalsEvaluator {

    /// Evaluate `goal` for the window ending at `goal.deadline`.
    /// Returns a `GoalWeeklyResult` ready to append. Caller decides
    /// whether to flip the goal's status (oneShot) or roll the
    /// deadline forward (weekly/biweekly/monthly).
    public static func evaluate(
        goal: Goal,
        transactions: [Transaction],
        rationale: GoalRationaleProvider = LocalGoalRationaleProvider(),
        now: Date = Date()
    ) -> GoalWeeklyResult {
        let windowEnd = goal.deadline
        let windowStart = startOfWindow(for: goal, endingAt: windowEnd)

        let actual = actualValue(
            for: goal.target,
            goal: goal,
            transactions: transactions,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
        let hit = goal.target.hit(actual: actual)
        let target = goal.target.displayValue
        let delta = actual - target
        let outcome: GoalWeeklyResult.Outcome = hit ? .hit : .missed

        let rationaleText = rationale.rationale(
            for: goal,
            actual: actual,
            target: target,
            windowStart: windowStart,
            windowEnd: windowEnd,
            outcome: outcome
        )

        return GoalWeeklyResult(
            windowStart: windowStart,
            windowEnd: windowEnd,
            targetValue: target,
            actualValue: actual,
            outcome: outcome,
            delta: delta,
            rationaleText: rationaleText,
            evaluatedAt: now
        )
    }

    /// Window length depends on cadence. v1 ships weekly only;
    /// helpers reserve the other cadences.
    public static func startOfWindow(for goal: Goal, endingAt end: Date) -> Date {
        let cal = Calendar.current
        switch goal.cadence {
        case .weekly:    return cal.date(byAdding: .day,   value: -7,  to: end) ?? end
        case .biweekly:  return cal.date(byAdding: .day,   value: -14, to: end) ?? end
        case .monthly:   return cal.date(byAdding: .month, value: -1,  to: end) ?? end
        case .oneShot:   return goal.createdAt
        }
    }

    // MARK: - Actuals per target shape

    private static func actualValue(
        for target: GoalTarget,
        goal: Goal,
        transactions: [Transaction],
        windowStart: Date,
        windowEnd: Date
    ) -> Decimal {
        switch target {
        case .spendUnder:
            return sumSpend(
                transactions: transactions,
                categoryLabel: goal.categoryLabel,
                merchantKey: nil,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
        case .saveAtLeast:
            return sumInflow(
                transactions: transactions,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
        case .merchantCancelled(let merchantKey):
            // 1 if NO charges from the merchant in the window, else 0.
            let charges = transactions.filter { tx in
                guard let amt = tx.amount, amt < 0, !tx.pending else { return false }
                guard tx.date >= windowStart, tx.date <= windowEnd else { return false }
                return tx.name.uppercased().contains(merchantKey.uppercased())
            }
            return charges.isEmpty ? 1 : 0
        case .countAtMost:
            // Number of distinct merchants we'd flag as unused
            // subscriptions in the window. Approximation: count
            // distinct uppercased-merchant strings on debit
            // transactions in the SUBSCRIPTIONS category.
            let cat = (goal.categoryLabel ?? "SUBSCRIPTIONS").uppercased()
            let inCategory = transactions.filter { tx in
                guard let amt = tx.amount, amt < 0, !tx.pending else { return false }
                guard tx.date >= windowStart, tx.date <= windowEnd else { return false }
                if case .knownCategory(let s) = tx.category {
                    return s.uppercased() == cat
                }
                return false
            }
            let uniqueMerchants = Set(inCategory.map { $0.name.uppercased() })
            return Decimal(uniqueMerchants.count)
        }
    }

    private static func sumSpend(
        transactions: [Transaction],
        categoryLabel: String?,
        merchantKey: String?,
        windowStart: Date,
        windowEnd: Date
    ) -> Decimal {
        var total: Decimal = 0
        for tx in transactions {
            guard let amount = tx.amount, amount < 0, !tx.pending else { continue }
            guard tx.date >= windowStart, tx.date <= windowEnd else { continue }
            if let label = categoryLabel {
                if case .knownCategory(let s) = tx.category {
                    guard s.uppercased() == label.uppercased() else { continue }
                } else { continue }
            }
            if let merchant = merchantKey {
                guard tx.name.uppercased().contains(merchant.uppercased()) else { continue }
            }
            total += abs(amount)
        }
        return total
    }

    private static func sumInflow(
        transactions: [Transaction],
        windowStart: Date,
        windowEnd: Date
    ) -> Decimal {
        var total: Decimal = 0
        for tx in transactions {
            guard let amount = tx.amount, amount > 0, !tx.pending else { continue }
            guard tx.date >= windowStart, tx.date <= windowEnd else { continue }
            total += amount
        }
        return total
    }
}
