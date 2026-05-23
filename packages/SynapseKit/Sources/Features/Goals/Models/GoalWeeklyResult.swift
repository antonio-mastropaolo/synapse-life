import Foundation

/// A single end-of-window evaluation result. Append-only on the
/// owning Goal. The store caps history at 26 entries (half a year of
/// weekly results) to keep the JSON file bounded.
public struct GoalWeeklyResult: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let windowStart: Date
    public let windowEnd: Date
    public let targetValue: Decimal
    public let actualValue: Decimal
    public let outcome: Outcome
    public let delta: Decimal              // signed: positive = over, negative = under
    public let rationaleText: String?
    public let evaluatedAt: Date

    public enum Outcome: String, Sendable, Hashable, Codable {
        case hit, missed, partial
    }

    public init(
        id: UUID = UUID(),
        windowStart: Date,
        windowEnd: Date,
        targetValue: Decimal,
        actualValue: Decimal,
        outcome: Outcome,
        delta: Decimal,
        rationaleText: String? = nil,
        evaluatedAt: Date = Date()
    ) {
        self.id = id
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.targetValue = targetValue
        self.actualValue = actualValue
        self.outcome = outcome
        self.delta = delta
        self.rationaleText = rationaleText
        self.evaluatedAt = evaluatedAt
    }
}
