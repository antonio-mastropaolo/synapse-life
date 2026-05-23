import Foundation

/// What "winning" a goal means, in concrete numbers. The evaluator
/// switches on this — `.spendUnder` and `.saveAtLeast` have inverted
/// progress math, and `.merchantCancelled` is binary.
public enum GoalTarget: Sendable, Hashable, Codable {
    case spendUnder(Decimal)                          // weekly cap
    case saveAtLeast(Decimal)                         // cumulative
    case merchantCancelled(merchantKey: String)       // pass/fail
    case countAtMost(Int)                             // e.g. at most 3 unused subs

    /// Numeric target as a Decimal where applicable. Used by the row
    /// and detail views for display.
    public var displayValue: Decimal {
        switch self {
        case .spendUnder(let v):    return v
        case .saveAtLeast(let v):   return v
        case .merchantCancelled:    return 0
        case .countAtMost(let n):   return Decimal(n)
        }
    }

    /// Returns progress as a 0...1 value given a current actual value.
    /// `.spendUnder` inverts (closer to 0 = better progress); the
    /// progress fraction is `1 - actual/target` clamped.
    public func progress(actual: Decimal) -> Double {
        switch self {
        case .spendUnder(let target):
            guard target > 0 else { return 0 }
            let ratio = nsd(actual) / nsd(target)
            return max(0, min(1, 1 - ratio))
        case .saveAtLeast(let target):
            guard target > 0 else { return 0 }
            return max(0, min(1, nsd(actual) / nsd(target)))
        case .merchantCancelled:
            return actual > 0 ? 1 : 0
        case .countAtMost(let target):
            guard target > 0 else { return 0 }
            let ratio = nsd(actual) / Double(target)
            return max(0, min(1, 1 - ratio))
        }
    }

    /// "Hit" verdict for an evaluation window's actual value.
    public func hit(actual: Decimal) -> Bool {
        switch self {
        case .spendUnder(let target):       return actual <= target
        case .saveAtLeast(let target):      return actual >= target
        case .merchantCancelled:            return actual > 0
        case .countAtMost(let target):      return actual <= Decimal(target)
        }
    }

    private func nsd(_ d: Decimal) -> Double {
        (d as NSDecimalNumber).doubleValue
    }
}
