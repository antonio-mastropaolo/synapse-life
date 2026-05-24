import Foundation

/// Generates the human-readable "you missed by $42" sentence on each
/// weekly result. Protocol so a future `LLMGoalRationaleProvider` can
/// be swapped in via `GoalsStore.init` without touching the evaluator
/// or view code.
public protocol GoalRationaleProvider: Sendable {
    func rationale(
        for goal: Goal,
        actual: Decimal,
        target: Decimal,
        windowStart: Date,
        windowEnd: Date,
        outcome: GoalWeeklyResult.Outcome
    ) -> String
}

/// Local synthesis — deterministic, free, instant. Good enough for v1.
public struct LocalGoalRationaleProvider: GoalRationaleProvider {
    public init() {}

    public func rationale(
        for goal: Goal,
        actual: Decimal,
        target: Decimal,
        windowStart: Date,
        windowEnd: Date,
        outcome: GoalWeeklyResult.Outcome
    ) -> String {
        let dollars: (Decimal) -> String = { d in
            d.formatted(.currency(code: "USD"))
        }
        switch goal.target {
        case .spendUnder:
            let label = goal.categoryLabel ?? "this category"
            let delta = abs(actual - target)
            if outcome == .hit {
                return "You spent \(dollars(actual)) on \(label) this week — that's \(dollars(delta)) under your \(dollars(target)) cap. Nice."
            } else {
                return "You spent \(dollars(actual)) on \(label) — \(dollars(delta)) over your \(dollars(target)) cap. The shortfall is the cheapest place to recover next week."
            }
        case .saveAtLeast:
            if outcome == .hit {
                return "You set aside \(dollars(actual)) this week — beat your \(dollars(target)) target."
            } else {
                let delta = target - actual
                return "Saved \(dollars(actual)) — \(dollars(delta)) short of your \(dollars(target)) target. Move any leftover restaurant budget here on Sunday."
            }
        case .merchantCancelled(let merchantKey):
            if outcome == .hit {
                return "No charges from \(merchantKey) this week — cancellation looks sticky."
            } else {
                return "\(merchantKey) charged again this week. The cancellation may not have stuck — open the membership detail to retry."
            }
        case .countAtMost(let cap):
            let n = (actual as NSDecimalNumber).intValue
            if outcome == .hit {
                return "Trimmed to \(n) recurring services, at or below your cap of \(cap)."
            } else {
                return "Currently at \(n) recurring services, \(n - cap) over your cap. The biggest line items are the cheapest to cut first."
            }
        }
    }
}
