import SwiftUI
import DesignSystem

/// Goals grouped by status. Active first (most prominent), then
/// Completed, then Missed, then Archived. Each section keeps its
/// own card so the visual rhythm is clear.
@MainActor
struct GoalsList: View {
    let goals: [Goal]
    let tokens: TokenSet
    let onSelectGoal: (Goal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("ACTIVE", goals.filter { $0.status == .active })
            section("COMPLETED", goals.filter { $0.status == .completed })
            section("MISSED", goals.filter { $0.status == .missed })
            section("ARCHIVED", goals.filter { $0.status == .archived })
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Goal]) -> some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { goal in
                        GoalRow(goal: goal, tokens: tokens) {
                            onSelectGoal(goal)
                        }
                        if goal.id != items.last?.id {
                            Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tokens.surface.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
                )
            }
        }
    }
}
