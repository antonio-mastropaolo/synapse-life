import Foundation
import Observation
import Models

/// Single source of truth for tracked goals.
///
/// - Mutations persist synchronously to a JSON file in Application
///   Support after every write (small file, infrequent writes — async
///   would over-engineer).
/// - `evaluatePendingWindows(transactions:now:)` is the foreground
///   evaluation entrypoint: walks every active goal whose deadline
///   has passed, appends a `GoalWeeklyResult`, rolls the deadline
///   forward (or marks `.completed`/`.missed` for `.oneShot`), and
///   pushes the new results onto `unseenResults` for the toast view.
/// - `applyAITip` is the lone "creation from AI" entrypoint — every
///   AI signal tile constructs an `AITipDescriptor` and hands it to
///   this method.
@MainActor
@Observable
public final class GoalsStore {
    public private(set) var goals: [Goal] = []
    public private(set) var unseenResults: [GoalWeeklyResult] = []
    public private(set) var lastEvaluationAt: Date?

    private let persistence: GoalsPersistence
    private let rationale: GoalRationaleProvider
    private let usesSampleData: Bool

    public init(
        persistence: GoalsPersistence = .default,
        rationale: GoalRationaleProvider = LocalGoalRationaleProvider(),
        usesSampleData: Bool = true
    ) {
        self.persistence = persistence
        self.rationale = rationale
        self.usesSampleData = usesSampleData
        loadOrSeed()
    }

    // MARK: - CRUD

    public func add(_ goal: Goal) {
        goals.append(goal)
        persist()
    }

    public func remove(id: UUID) {
        goals.removeAll { $0.id == id }
        persist()
    }

    public func update(id: UUID, transform: (inout Goal) -> Void) {
        guard let idx = goals.firstIndex(where: { $0.id == id }) else { return }
        transform(&goals[idx])
        persist()
    }

    public func archive(id: UUID) {
        update(id: id) { $0.status = .archived }
    }

    // MARK: - AI tip → Goal

    /// Convert an AI tip descriptor into a real goal. The store
    /// decides target shape based on `suggestedKind` + the parsed
    /// amount; the caller doesn't need to know.
    @discardableResult
    public func applyAITip(_ tip: AITipDescriptor, now: Date = Date()) -> Goal {
        let cadence = GoalCadence.weekly
        let deadline = cadence.nextDeadline(after: now)

        let target: GoalTarget
        switch tip.suggestedKind {
        case .reduceCategorySpend:
            target = .spendUnder(tip.parsedTargetAmount ?? 200)
        case .capMerchantSpend:
            target = .spendUnder(tip.parsedTargetAmount ?? 100)
        case .cancelSubscription:
            target = .merchantCancelled(merchantKey: tip.categoryHint ?? "subscription")
        case .increaseSavings, .buildEmergencyFund:
            target = .saveAtLeast(tip.parsedTargetAmount ?? 500)
        case .custom:
            target = .spendUnder(tip.parsedTargetAmount ?? 100)
        }

        let goal = Goal(
            kind: tip.suggestedKind,
            title: tip.title,
            target: target,
            categoryLabel: tip.categoryHint,
            cadence: cadence,
            deadline: deadline,
            createdAt: now,
            sourceAITipID: tip.id,
            sourceAITipText: tip.detailText
        )
        add(goal)
        return goal
    }

    // MARK: - Evaluation

    /// True if it's been ≥ 6 days since the last evaluation. Used by
    /// the app shells to decide whether to call `evaluatePendingWindows`
    /// on foreground.
    public func isEvaluationDue(now: Date = Date()) -> Bool {
        guard let last = lastEvaluationAt else { return true }
        return now.timeIntervalSince(last) >= (6 * 86_400)
    }

    /// Walk every active goal whose deadline has passed. Append a
    /// result, roll the deadline forward, push onto `unseenResults`.
    public func evaluatePendingWindows(
        transactions: [Transaction],
        now: Date = Date()
    ) {
        var produced: [GoalWeeklyResult] = []
        for index in goals.indices {
            guard goals[index].status == .active else { continue }
            guard goals[index].deadline <= now else { continue }

            let result = GoalsEvaluator.evaluate(
                goal: goals[index],
                transactions: transactions,
                rationale: rationale,
                now: now
            )
            goals[index].weeklyResults.append(result)
            // Cap history at 26 entries.
            if goals[index].weeklyResults.count > 26 {
                goals[index].weeklyResults.removeFirst(
                    goals[index].weeklyResults.count - 26
                )
            }
            // Roll forward (or terminate, for .oneShot).
            switch goals[index].cadence {
            case .oneShot:
                goals[index].status = (result.outcome == .hit) ? .completed : .missed
            case .weekly, .biweekly, .monthly:
                goals[index].deadline = goals[index].cadence.nextDeadline(after: now)
            }
            produced.append(result)
        }
        if !produced.isEmpty {
            // Keep only the most-recent window of results for the
            // toast — protect against the "user away 6 weeks" storm.
            let cutoff = (produced.map(\.windowEnd).max() ?? now).addingTimeInterval(-86_400)
            unseenResults = produced.filter { $0.windowEnd >= cutoff }
        }
        lastEvaluationAt = now
        persist()
    }

    public func markResultsSeen() {
        unseenResults.removeAll()
        persist()
    }

    // MARK: - Loading

    private func loadOrSeed() {
        do {
            let loaded = try persistence.load()
            if loaded.isEmpty, usesSampleData {
                goals = GoalsSampleSeeder.seed()
                persist()
            } else {
                goals = loaded
            }
        } catch {
            // Corrupt file — seed and overwrite. Surfacing this to
            // the UI would over-design v1.
            goals = usesSampleData ? GoalsSampleSeeder.seed() : []
            persist()
        }
    }

    private func persist() {
        do {
            try persistence.save(goals)
        } catch {
            // Disk write failed — log and continue. Goals stay in
            // memory; next mutation will retry.
        }
    }
}
