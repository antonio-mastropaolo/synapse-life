import SwiftUI
import DesignSystem

/// Modal triggered by an "Apply as goal" button on an AI tile. Lets
/// the user confirm/edit title, target amount, and deadline before
/// committing the goal to the store.
@MainActor
public struct GoalApplySheet: View {
    public let tip: AITipDescriptor
    @Bindable public var store: GoalsStore
    public var onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var title: String
    @State private var amount: String
    @State private var hasRequestedNotifications = false

    public init(
        tip: AITipDescriptor,
        store: GoalsStore,
        onDismiss: @escaping () -> Void
    ) {
        self.tip = tip
        self.store = store
        self.onDismiss = onDismiss
        _title = State(initialValue: tip.title)
        let initialAmount: Decimal = tip.parsedTargetAmount ?? 200
        _amount = State(initialValue: String(describing: initialAmount))
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 18) {
            header(tokens: tokens)
            originCard(tokens: tokens)
            field(label: "Goal title", tokens: tokens) {
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tokens.foregroundSecondary.color.opacity(0.10))
                    )
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            field(label: "Target ($)", tokens: tokens) {
                TextField("", text: $amount)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tokens.foregroundSecondary.color.opacity(0.10))
                    )
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
            }
            notifyHint(tokens: tokens)
            actions(tokens: tokens)
        }
        .padding(28)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.20), lineWidth: 1)
        )
    }

    private func header(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
            Text("Apply this AI tip as a goal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .buttonStyle(.plain)
        }
    }

    private func originCard(tokens: TokenSet) -> some View {
        Text(tip.detailText)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(tokens.foregroundSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.foregroundSecondary.color.opacity(0.07))
            )
    }

    @ViewBuilder
    private func field<Content: View>(
        label: String,
        tokens: TokenSet,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            content()
        }
    }

    private func notifyHint(tokens: TokenSet) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.27, green: 0.83, blue: 0.89))
            Text("We'll let you know each Sunday how this goal landed.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
        }
    }

    private func actions(tokens: TokenSet) -> some View {
        HStack(spacing: 12) {
            Spacer()
            Button { onDismiss() } label: {
                Text("Cancel")
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
                commit()
            } label: {
                Text("Add goal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 1.00, green: 0.69, blue: 0.22))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func commit() {
        let parsed = Decimal(string: amount.replacingOccurrences(of: "$", with: ""))
        let descriptor = AITipDescriptor(
            id: tip.id,
            title: title,
            detailText: tip.detailText,
            icon: tip.icon,
            suggestedKind: tip.suggestedKind,
            categoryHint: tip.categoryHint,
            parsedTargetAmount: parsed ?? tip.parsedTargetAmount
        )
        _ = store.applyAITip(descriptor)
        Task {
            // First "apply as goal" is the intent signal — ask for
            // notification permission now, not at cold launch.
            _ = await NotificationGate.shared.requestIfNeeded()
            await NotificationGate.shared.scheduleRecurringWeeklyReminderIfNeeded()
        }
        onDismiss()
    }
}
