import Foundation

/// A tracked goal. Spawned from an AI tip ("cap restaurants at $200")
/// or created manually. The evaluator marks each goal hit/missed at
/// the end of its cadence window and appends a `GoalWeeklyResult` to
/// `weeklyResults`. Goals roll forward — a `.completed` goal carries
/// its terminal result; an active goal rolls its `deadline` forward
/// to the next window.
public struct Goal: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public var kind: GoalKind
    public var title: String
    public var target: GoalTarget
    public var categoryLabel: String?
    public var merchantKey: String?
    public var cadence: GoalCadence
    public var deadline: Date
    public let createdAt: Date
    public var status: GoalStatus
    public var weeklyResults: [GoalWeeklyResult]
    public var sourceAITipID: UUID?
    public var sourceAITipText: String?
    public var isSample: Bool

    public init(
        id: UUID = UUID(),
        kind: GoalKind,
        title: String,
        target: GoalTarget,
        categoryLabel: String? = nil,
        merchantKey: String? = nil,
        cadence: GoalCadence = .weekly,
        deadline: Date,
        createdAt: Date = Date(),
        status: GoalStatus = .active,
        weeklyResults: [GoalWeeklyResult] = [],
        sourceAITipID: UUID? = nil,
        sourceAITipText: String? = nil,
        isSample: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.target = target
        self.categoryLabel = categoryLabel
        self.merchantKey = merchantKey
        self.cadence = cadence
        self.deadline = deadline
        self.createdAt = createdAt
        self.status = status
        self.weeklyResults = weeklyResults
        self.sourceAITipID = sourceAITipID
        self.sourceAITipText = sourceAITipText
        self.isSample = isSample
    }
}

/// Cadence of evaluation. v1 ships `.weekly` only; the other cases
/// reserve the enum slot so future cadences don't break the codable
/// wire format.
public enum GoalCadence: String, Sendable, Hashable, Codable {
    case weekly, biweekly, monthly, oneShot

    /// The next deadline (end-of-window) given a starting reference.
    /// Always rounds forward to the end of the current week in the
    /// user's local calendar — Sunday 23:59:59 — so weekly evaluators
    /// have a stable target regardless of when the goal was created.
    public func nextDeadline(after now: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.timeZone = TimeZone.current
        switch self {
        case .weekly:
            return endOfWeek(from: now, in: cal)
        case .biweekly:
            let oneWeekOut = cal.date(byAdding: .day, value: 7, to: now) ?? now
            return endOfWeek(from: oneWeekOut, in: cal)
        case .monthly:
            return endOfMonth(from: now, in: cal)
        case .oneShot:
            // Same as weekly for v1; oneShot goals just don't roll.
            return endOfWeek(from: now, in: cal)
        }
    }

    private func endOfWeek(from now: Date, in cal: Calendar) -> Date {
        // Calendar's "next weekday" rounds forward to the next Sunday;
        // we then push to 23:59:59.
        let comps = DateComponents(hour: 23, minute: 59, second: 59, weekday: 1)
        let next = cal.nextDate(
            after: now,
            matching: comps,
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? now
        return next
    }

    private func endOfMonth(from now: Date, in cal: Calendar) -> Date {
        let comps = cal.dateComponents([.year, .month], from: now)
        var start = DateComponents()
        start.year = comps.year
        start.month = (comps.month ?? 1) + 1
        start.day = 1
        start.hour = 23
        start.minute = 59
        start.second = 59
        guard let first = cal.date(from: start) else { return now }
        return cal.date(byAdding: .day, value: -1, to: first) ?? first
    }
}

public enum GoalStatus: String, Sendable, Hashable, Codable {
    case active
    case completed
    case missed
    case archived
}
