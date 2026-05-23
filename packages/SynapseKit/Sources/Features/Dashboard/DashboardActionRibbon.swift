import SwiftUI
import DesignSystem

/// Sticky bottom toolbar for the Dashboard.
///
///   [ N of TOTAL ]   [ Mark N as reviewed ] | [ Mark all ] [ Skip all ]
///
/// Replaces the old `footer` + iOS FAB pair so the two platforms share
/// the same affordances. The primary button paints its accent fill
/// only when `selectionCount > 0`; under Reduce Motion the press
/// scale is dropped.
@MainActor
struct DashboardActionRibbon: View {

    let footerText: String
    let selectionCount: Int

    /// Action handlers. `markSelected` is required; `markAll` and
    /// `skipAll` are the secondary affordances on the right.
    var markSelected: () -> Void
    var markAll: () -> Void
    var skipAll: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var primaryPressed = false

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 12) {
            Text(footerText)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .contentTransition(.numericText())

            Spacer()

            primaryButton(tokens: tokens)

            Divider()
                .frame(height: 18)
                .background(tokens.foregroundSecondary.color.opacity(0.30))

            secondaryButton(
                label: "Mark all", tokens: tokens, action: markAll
            )
            secondaryButton(
                label: "Skip all", tokens: tokens, action: skipAll
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tokens.background.color)
    }

    @ViewBuilder
    private func primaryButton(tokens: TokenSet) -> some View {
        let enabled = selectionCount > 0
        Button(action: { markSelected() }) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Mark \(selectionCount) as reviewed")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(enabled ? tokens.accent.color : tokens.surface.color)
            )
            .foregroundStyle(enabled ? Color.white : tokens.foregroundSecondary.color)
            .scaleEffect(primaryPressed && !reduceMotion ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !reduceMotion, !primaryPressed else { return }
                    withAnimation(.easeOut(duration: 0.10)) { primaryPressed = true }
                }
                .onEnded { _ in
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 0.12)) { primaryPressed = false }
                }
        )
        .accessibilityLabel(
            enabled
            ? "Mark \(selectionCount) transactions as reviewed"
            : "Select a transaction to mark as reviewed"
        )
    }

    @ViewBuilder
    private func secondaryButton(
        label: String, tokens: TokenSet, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
