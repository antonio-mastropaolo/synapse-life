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
