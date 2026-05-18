import SwiftUI
import DesignSystem

/// Slides in from the bottom-right when there are unseen weekly
/// results. Tapping opens the Goals surface; dismissing marks the
/// results as seen.
@MainActor
public struct GoalsToastView: View {
    @Bindable private var store: GoalsStore
    private let onOpen: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(store: GoalsStore, onOpen: @escaping () -> Void) {
        self.store = store
        self.onOpen = onOpen
    }

    public var body: some View {
        if store.unseenResults.isEmpty {
            EmptyView()
        } else {
            let tokens = theme.tokens(for: scheme)
            let hits = store.unseenResults.filter { $0.outcome == .hit }.count
            let total = store.unseenResults.count
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.69, blue: 0.22).opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly check-in")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("\(hits) of \(total) goals hit this week")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Spacer()
                Button {
                    store.markResultsSeen()
                    onOpen()
                } label: {
                    Text("OPEN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(red: 1.0, green: 0.69, blue: 0.22))
                        )
                }
                .buttonStyle(.plain)
                Button {
                    store.markResultsSeen()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tokens.surface.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tokens.foregroundSecondary.color.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
            .padding(20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
