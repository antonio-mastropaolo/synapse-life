import SwiftUI
import DesignSystem

/// Small horizontal strip designed to sit on the dashboard right
/// rail. Shows up to 3 active goals with mini progress rings + short
/// titles. Tap routes to the Goals surface. Renders nothing when
/// there are no active goals.
@MainActor
public struct GoalsBanner: View {
    @Bindable private var store: GoalsStore
    private let openGoals: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(store: GoalsStore, openGoals: @escaping () -> Void) {
        self.store = store
        self.openGoals = openGoals
    }

    public var body: some View {
        let activeGoals = store.goals
            .filter { $0.status == .active }
            .prefix(3)
        if activeGoals.isEmpty {
            EmptyView()
        } else {
            let tokens = theme.tokens(for: scheme)
            Button { openGoals() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
                        Text("GOALS THIS WEEK")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(tokens.foregroundSecondary.color)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(activeGoals) { goal in
                            goalPill(goal: goal, tokens: tokens)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tokens.surface.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func goalPill(goal: Goal, tokens: TokenSet) -> some View {
        let progress = goal.weeklyResults.last
            .map { goal.target.progress(actual: $0.actualValue) } ?? 0.02
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(goal.kind.tint.opacity(0.20), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(progress, 1.0)))
                    .stroke(goal.kind.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            Text(goal.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(1)
            Spacer()
        }
    }
}
