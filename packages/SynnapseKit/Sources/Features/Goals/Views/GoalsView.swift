import SwiftUI
import DesignSystem

/// Main Goals surface. Replaces `GoalsPlaceholderView`. Layout:
///
///   • Header — title + summary copy.
///   • Last-week recap card — surfaces the most-recent weekly result.
///   • Goals list grouped by status (Active / Completed / Missed / Archived).
///   • Footer hint — "goals usually come from AI tips; open
///     Transactions or the Dashboard to apply one".
@MainActor
public struct GoalsView: View {
    @Bindable private var store: GoalsStore
    private let openTransactions: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var selectedGoalID: UUID?

    public init(store: GoalsStore, openTransactions: @escaping () -> Void = {}) {
        self.store = store
        self.openTransactions = openTransactions
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        if let id = selectedGoalID {
            GoalDetailView(store: store, goalId: id) {
                selectedGoalID = nil
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header(tokens: tokens)
                    recapCard(tokens: tokens)
                    if store.goals.isEmpty {
                        emptyState(tokens: tokens)
                    } else {
                        GoalsList(goals: store.goals, tokens: tokens) { goal in
                            selectedGoalID = goal.id
                        }
                    }
                    footerHint(tokens: tokens)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(tokens.background.color)
        }
    }

    // MARK: - Pieces

    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goals")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Each goal is monitored weekly. Synapse fires a notification and an in-app check-in on Sunday with what landed.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func recapCard(tokens: TokenSet) -> some View {
        let recentResults = store.goals
            .flatMap { goal in goal.weeklyResults.suffix(1).map { (goal, $0) } }
            .sorted { $0.1.evaluatedAt > $1.1.evaluatedAt }
            .prefix(1)
        if let (goal, latest) = recentResults.first {
            let tone: Color = latest.outcome == .hit
                ? Color(red: 0.34, green: 0.78, blue: 0.50)
                : Color(red: 0.94, green: 0.33, blue: 0.56)
            HStack(spacing: 14) {
                Image(systemName: latest.outcome == .hit
                      ? "checkmark.seal.fill"
                      : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tone)
                VStack(alignment: .leading, spacing: 4) {
                    Text("LATEST WEEKLY RESULT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text(goal.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    if let rationale = latest.rationaleText {
                        Text(rationale)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tokens.surface.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tone.opacity(0.40), lineWidth: 1)
            )
        }
    }

    private func emptyState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No goals tracked yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Open Transactions, tap a category card, and use 'Apply as goal' on any AI signal to start tracking.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.vertical, 40)
    }

    private func footerHint(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
            Text("Goals usually come from AI tips. Open Transactions or the Dashboard, tap a card, and apply any insight you want to track.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            Button(action: openTransactions) {
                Text("Open Transactions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.06))
        )
    }
}
