import Foundation

/// Seeds three sample goals on first launch when demo data is on.
/// Every goal carries `isSample: true` so the row paints the orange
/// SAMPLE chip — same treatment as the dashboard AI cards.
public enum GoalsSampleSeeder {

    public static func seed(now: Date = Date()) -> [Goal] {
        let cadence = GoalCadence.weekly
        let nextDeadline = cadence.nextDeadline(after: now)

        // Restaurants — pre-populate two weekly results so the
        // detail timeline isn't empty.
        let restaurantsHistory: [GoalWeeklyResult] = [
            GoalWeeklyResult(
                windowStart: now.addingTimeInterval(-14 * 86_400),
                windowEnd:   now.addingTimeInterval(-7 * 86_400),
                targetValue: 200,
                actualValue: 173,
                outcome: .hit,
                delta: -27,
                rationaleText: "Hit the cap by $27 last week — restaurants were quieter than your typical Friday."
            ),
            GoalWeeklyResult(
                windowStart: now.addingTimeInterval(-7 * 86_400),
                windowEnd:   now,
                targetValue: 200,
                actualValue: 242,
                outcome: .missed,
                delta: 42,
                rationaleText: "Missed by $42 — Tuesday's BNPL-adjacent dinner ($58) was the largest swing."
            )
        ]
        let restaurants = Goal(
            kind: .reduceCategorySpend,
            title: "Cap Restaurants at $200/wk",
            target: .spendUnder(200),
            categoryLabel: "RESTAURANTS",
            cadence: cadence,
            deadline: nextDeadline,
            createdAt: now.addingTimeInterval(-20 * 86_400),
            weeklyResults: restaurantsHistory,
            sourceAITipText: "AI Suggests: Cap Restaurants at $200 for the next 14 days. Reach the previous average and you free $42 for goal progress.",
            isSample: true
        )

        let subs = Goal(
            kind: .cancelSubscription,
            title: "Trim recurring services to 3 or fewer",
            target: .countAtMost(3),
            categoryLabel: "SUBSCRIPTIONS",
            cadence: cadence,
            deadline: nextDeadline,
            createdAt: now.addingTimeInterval(-7 * 86_400),
            weeklyResults: [
                GoalWeeklyResult(
                    windowStart: now.addingTimeInterval(-7 * 86_400),
                    windowEnd:   now,
                    targetValue: 3,
                    actualValue: 4,
                    outcome: .missed,
                    delta: 1,
                    rationaleText: "Currently at 4 recurring services. The Audio Subscription ($17) is the cheapest to cut first."
                )
            ],
            sourceAITipText: "Audit the 3 services you haven't opened in 60+ days.",
            isSample: true
        )

        let cushion = Goal(
            kind: .buildEmergencyFund,
            title: "Build a $500 emergency cushion",
            target: .saveAtLeast(500),
            cadence: cadence,
            deadline: nextDeadline,
            createdAt: now.addingTimeInterval(-3 * 86_400),
            weeklyResults: [],
            sourceAITipText: "Quarterly Tax Reserve — you receive freelance income; a tax reserve avoids the April crunch.",
            isSample: true
        )

        return [restaurants, subs, cushion]
    }
}
