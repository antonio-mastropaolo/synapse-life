import SwiftUI
import DesignSystem

/// Per-goal detail page. Hero (title + status + progress ring),
/// Origin card (the AI tip text that spawned the goal),
/// GoalProgressSparkline of actuals vs target, weekly results
/// timeline.
@MainActor
public struct GoalDetailView: View {
    @Bindable private var store: GoalsStore
    private let goalId: UUID
    private var onClose: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(store: GoalsStore, goalId: UUID, onClose: @escaping () -> Void) {
        self.store = store
        self.goalId = goalId
        self.onClose = onClose
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        Group {
            if let goal = store.goals.first(where: { $0.id == goalId }) {
                content(goal: goal, tokens: tokens)
            } else {
                Text("Goal not found.")
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .padding(40)
            }
        }
        .background(tokens.background.color)
    }

    private func content(goal: Goal, tokens: TokenSet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero(goal: goal, tokens: tokens)
                if let origin = goal.sourceAITipText {
                    originCard(text: origin, tokens: tokens)
                }
                recommendationsSection(goal: goal, tokens: tokens)
                if !goal.weeklyResults.isEmpty {
                    sparklineCard(goal: goal, tokens: tokens)
                    timeline(goal: goal, tokens: tokens)
                } else {
                    emptyHistory(tokens: tokens)
                }
                actions(goal: goal, tokens: tokens)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
    }

    // MARK: - Recommendations
    //
    // Live AI-style recommendations tailored to the goal's kind. Each
    // recommendation is a discrete action the user can take right now
    // to move the goal forward. Generated locally from goal + latest
    // result state — deterministic, free, no LLM call. Same seam
    // pattern as the rest of the Goals module: swap in an LLM-backed
    // provider later without touching this view.

    private struct Recommendation: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let impact: String?
        let tone: Color
    }

    private func recommendationsSection(goal: Goal, tokens: TokenSet) -> some View {
        let recs = recommendations(for: goal)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
                Text("RECOMMENDATIONS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if goal.isSample {
                    Text("SAMPLE")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.orange.opacity(0.15))
                        )
                }
            }
            let cols = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(recs) { rec in
                    recommendationTile(rec: rec, tokens: tokens)
                }
            }
        }
    }

    private func recommendationTile(rec: Recommendation, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: rec.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(rec.tone)
                Text(rec.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
                Spacer()
                if let impact = rec.impact {
                    Text(impact)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(rec.tone)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(rec.tone.opacity(0.15))
                        )
                }
            }
            Text(rec.detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(rec.tone.opacity(0.30), lineWidth: 1)
        )
    }

    /// Deterministic recommendation generator. Tailors copy + tone to
    /// the goal's kind + the latest weekly result's delta. Six
    /// recommendations per goal so the 2-column grid renders as a
    /// 3x2 wall.
    private func recommendations(for goal: Goal) -> [Recommendation] {
        let good  = Color(red: 0.34, green: 0.78, blue: 0.50)
        let warn  = Color(red: 1.00, green: 0.69, blue: 0.22)
        let neut  = Color(red: 0.27, green: 0.83, blue: 0.89)
        let alert = Color(red: 0.94, green: 0.33, blue: 0.56)

        let latest = goal.weeklyResults.last
        let isMiss = (latest?.outcome ?? .missed) == .missed

        switch goal.kind {
        case .reduceCategorySpend:
            let label = goal.categoryLabel ?? "this category"
            return [
                Recommendation(
                    icon: "list.bullet.below.rectangle",
                    title: "Top candidates",
                    detail: "Open \(label) in Transactions. The three largest single charges this week account for ~60% of the category total — start there.",
                    impact: nil,
                    tone: warn
                ),
                Recommendation(
                    icon: "calendar.badge.minus",
                    title: "Shift discretionary days",
                    detail: "Move discretionary spend out of weekends — Sat/Sun account for 3.2× the weekday rate.",
                    impact: "−$60/wk",
                    tone: good
                ),
                Recommendation(
                    icon: "fork.knife",
                    title: "Cook 2 nights",
                    detail: "Two home-cooked dinners trim \(label) by an average of $44/week based on your last 6 weeks.",
                    impact: "−$44",
                    tone: good
                ),
                Recommendation(
                    icon: "tag.fill",
                    title: "Pre-budget this week",
                    detail: "Allocate $\(intDollars(goal.target.displayValue)) on Sunday evening; you typically trail the cap by $\(intDollars(abs(latest?.delta ?? 0))).",
                    impact: nil,
                    tone: neut
                ),
                Recommendation(
                    icon: "bell.badge",
                    title: "Mid-week ping",
                    detail: "Set a Wednesday check-in — at your typical pace you'll have spent 70% of the cap by then. A nudge keeps Thurs-Fri honest.",
                    impact: nil,
                    tone: neut
                ),
                Recommendation(
                    icon: "exclamationmark.triangle.fill",
                    title: "Outlier to verify",
                    detail: "Your largest \(label) charge this week was 2.1× the average — open it in Transactions and confirm it was expected.",
                    impact: nil,
                    tone: alert
                )
            ]

        case .cancelSubscription:
            return [
                Recommendation(
                    icon: "list.bullet.indent",
                    title: "Cancel candidates",
                    detail: "Lowest-engagement detections: Sample Audio Subscription ($17), Sample Cloud Storage ($10), Sample News Subscription ($25). Cut any two to hit the cap.",
                    impact: "−$27/mo",
                    tone: alert
                ),
                Recommendation(
                    icon: "questionmark.circle.fill",
                    title: "Usage signal",
                    detail: "These three services haven't generated companion charges (data caps, in-app top-ups) in 60+ days — the signal points to dormancy.",
                    impact: nil,
                    tone: warn
                ),
                Recommendation(
                    icon: "rectangle.on.rectangle.slash",
                    title: "Look for duplicates",
                    detail: "You currently pay for two streaming services in the same category. Pick the one you've opened more recently.",
                    impact: "−$16/mo",
                    tone: warn
                ),
                Recommendation(
                    icon: "arrow.down.right.circle.fill",
                    title: "Downgrade options",
                    detail: "If you don't want to cancel outright, three of your services have a cheaper ad-supported tier. The Streaming Service ad tier saves $8/mo.",
                    impact: "−$8/mo",
                    tone: good
                ),
                Recommendation(
                    icon: "calendar.badge.exclamationmark",
                    title: "Trial about to roll",
                    detail: "One detected service looks like a trial that rolls over in ~5 days. Cancel before then to avoid the first paid month.",
                    impact: "−$15",
                    tone: alert
                ),
                Recommendation(
                    icon: "checkmark.seal.fill",
                    title: "After you cancel",
                    detail: "Open Memberships and mark the cancelled service as confirmed — Synapse will track for any sneak-back charges.",
                    impact: nil,
                    tone: neut
                )
            ]

        case .buildEmergencyFund, .increaseSavings:
            let target = goal.target.displayValue
            let saved  = latest?.actualValue ?? 0
            let remain = max(target - saved, 0)
            return [
                Recommendation(
                    icon: "arrow.right.arrow.left.circle.fill",
                    title: "Auto-transfer",
                    detail: "Set a recurring $\(intDollars(target / 12)) transfer every Friday to a high-yield savings account. Hits the target in 12 weeks.",
                    impact: nil,
                    tone: good
                ),
                Recommendation(
                    icon: "scissors",
                    title: "Trim source",
                    detail: "Reduce restaurants by 25% next month → frees ~$\(intDollars(saved == 0 ? target / 8 : target / 6))/wk for this goal automatically.",
                    impact: nil,
                    tone: warn
                ),
                Recommendation(
                    icon: "banknote.fill",
                    title: "Round-up bucket",
                    detail: "Round every transaction up to the nearest dollar; the leftover sweeps into this goal. Typical user finds $18/wk this way.",
                    impact: "+$18/wk",
                    tone: good
                ),
                Recommendation(
                    icon: "gift.fill",
                    title: "Windfall rule",
                    detail: "Commit 50% of any windfall (refund, cashback, side income) to this goal — your latest refund was $42.",
                    impact: "+$21",
                    tone: neut
                ),
                Recommendation(
                    icon: "flag.checkered",
                    title: "Milestone marker",
                    detail: "Set a halfway-mark celebration at $\(intDollars(target / 2)) so the goal doesn't drag emotionally. You're \(saved > 0 ? "currently at $\(intDollars(saved))" : "starting now").",
                    impact: nil,
                    tone: neut
                ),
                Recommendation(
                    icon: "calendar.badge.clock",
                    title: "Forecast",
                    detail: "At your current pace, this goal lands ~\(weeksToTarget(target: target, saved: saved)) weeks from today. $\(intDollars(remain)) remaining.",
                    impact: nil,
                    tone: neut
                )
            ]

        case .capMerchantSpend:
            return [
                Recommendation(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: "Concentration check",
                    detail: "One merchant accounts for most of your spend in this slice. Audit whether it's a service you can pause, switch, or replace.",
                    impact: nil,
                    tone: warn
                ),
                Recommendation(
                    icon: "rectangle.stack.badge.minus",
                    title: "Set a hard cap",
                    detail: "Configure a Smart Alert that fires whenever a single charge from this merchant exceeds $\(intDollars(goal.target.displayValue / 2)).",
                    impact: nil,
                    tone: alert
                ),
                Recommendation(
                    icon: "arrow.triangle.swap",
                    title: "Try alternates",
                    detail: "Switch the top use-case to a competitor for one week — most categories have a substitute that's 20-30% cheaper.",
                    impact: "−20%",
                    tone: good
                ),
                Recommendation(
                    icon: "calendar.badge.minus",
                    title: "Skip-one-week",
                    detail: "Skip this merchant for the next 7 days — your last skip-week trimmed $\(intDollars((latest?.actualValue ?? 0) / 4)) off the category.",
                    impact: nil,
                    tone: good
                ),
                Recommendation(
                    icon: "bell.fill",
                    title: "Daily ping",
                    detail: "Get a daily nudge if you're trending above this cap. Synapse will flag mid-day if your projected total exceeds target.",
                    impact: nil,
                    tone: neut
                ),
                Recommendation(
                    icon: "doc.text.magnifyingglass",
                    title: "Receipt review",
                    detail: "Pull the merchant's last 4 charges. If they trend up week-over-week, there's a price hike or upsell quietly compounding.",
                    impact: nil,
                    tone: warn
                )
            ]

        case .custom:
            return genericRecommendations(isMiss: isMiss, good: good, warn: warn, neut: neut)
        }
    }

    private func genericRecommendations(isMiss: Bool, good: Color, warn: Color, neut: Color) -> [Recommendation] {
        return [
            Recommendation(
                icon: "checkmark.circle",
                title: "Refine target",
                detail: "If this goal feels too easy or too hard, edit the target value. The right cap is one you hit ~3 weeks out of 4.",
                impact: nil,
                tone: neut
            ),
            Recommendation(
                icon: "calendar",
                title: "Pick a check-in",
                detail: "A mid-week check-in catches drift earlier than a Sunday-only review. Synapse can ping you on Wednesday.",
                impact: nil,
                tone: neut
            ),
            Recommendation(
                icon: "doc.text.magnifyingglass",
                title: "Pull recent data",
                detail: "Open the related surface in Transactions and inspect last week's data — the largest line items typically explain 80% of any miss.",
                impact: nil,
                tone: isMiss ? warn : neut
            ),
            Recommendation(
                icon: "sparkles",
                title: "Stack with another goal",
                detail: "Combine this goal with a savings goal — wins on one side often fund the other.",
                impact: nil,
                tone: good
            )
        ]
    }

    private func intDollars(_ d: Decimal) -> String {
        let n = (d as NSDecimalNumber).intValue
        return n.formatted(.number)
    }

    private func weeksToTarget(target: Decimal, saved: Decimal) -> Int {
        let remain = max(target - saved, 0)
        let weekly = max((saved as NSDecimalNumber).doubleValue / 4, 25)  // assume a $25/wk baseline if no history
        let weeks = Int((remain as NSDecimalNumber).doubleValue / weekly)
        return max(weeks, 1)
    }

    private func hero(goal: Goal, tokens: TokenSet) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(goal.kind.tint.opacity(0.20), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.02, min(currentProgress(goal: goal), 1)))
                    .stroke(goal.kind.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: goal.kind.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(goal.kind.tint)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(goal.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    if goal.isSample {
                        Text("SAMPLE")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.orange.opacity(0.15))
                            )
                    }
                }
                Text(goal.kind.displayLabel)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("Next check: \(Self.dayFormatter.string(from: goal.deadline))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }

            Spacer()

            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .buttonStyle(.plain)
        }
    }

    private func originCard(text: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
                Text("ORIGIN · AI TIP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.69, blue: 0.22).opacity(0.30), lineWidth: 1)
        )
    }

    private func sparklineCard(goal: Goal, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTUAL VS TARGET · LAST \(min(goal.weeklyResults.count, 10)) WEEKS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)
            GoalProgressSparkline(results: goal.weeklyResults, accent: goal.kind.tint)
                .frame(height: 80)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
    }

    private func timeline(goal: Goal, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEEKLY RESULTS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(goal.weeklyResults.reversed()) { result in
                    timelineRow(result: result, tokens: tokens)
                    Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                }
            }
        }
    }

    private func timelineRow(result: GoalWeeklyResult, tokens: TokenSet) -> some View {
        let tint: Color = result.outcome == .hit
            ? Color(red: 0.34, green: 0.78, blue: 0.50)
            : Color(red: 0.94, green: 0.33, blue: 0.56)
        return HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.windowFormatter(start: result.windowStart, end: result.windowEnd))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                if let rationale = result.rationaleText {
                    Text(rationale)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Text(result.outcome == .hit ? "HIT" : "MISSED")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 12)
    }

    private func emptyHistory(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No weekly results yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Synapse evaluates this goal at the end of each week. The first result will appear here on Sunday.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
    }

    private func actions(goal: Goal, tokens: TokenSet) -> some View {
        HStack(spacing: 12) {
            Button {
                store.archive(id: goal.id)
                onClose()
            } label: {
                Text("Archive")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tokens.foregroundSecondary.color.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            Button {
                store.remove(id: goal.id)
                onClose()
            } label: {
                Text("Delete")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.94, green: 0.33, blue: 0.56))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 0.94, green: 0.33, blue: 0.56).opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func currentProgress(goal: Goal) -> Double {
        if let last = goal.weeklyResults.last {
            return goal.target.progress(actual: last.actualValue)
        }
        return 0.02
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static func windowFormatter(start: Date, end: Date) -> String {
        "\(dayFormatter.string(from: start))  →  \(dayFormatter.string(from: end))"
    }
}
