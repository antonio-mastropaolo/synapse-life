import SwiftUI
import DesignSystem
import Models

/// Compact proactive-feed strip shown above the review queue. Surfaces the
/// `ProactiveAnalyzer`'s output — upcoming bills, brand-new recurrings, and
/// anomalous spend — that `AppCore` loaded from the durable
/// `ProactiveNotificationStore`. Hidden entirely when there are no signals, so
/// the dashboard renders unchanged until the analyzer has something to say.
///
/// Render-only for now: tapping a row calls `onTap` (wired to the inbox jump
/// target by the integrator). Dismissal lands with the nightly background task
/// that also writes `setDismissed` back to the store.
@MainActor
struct DashboardProactiveStrip: View {

    let signals: [ProactiveSignal]
    let tokens: TokenSet
    /// Cap so the strip never crowds out the review queue. The store already
    /// returns urgency-first, so the top slice is the most important.
    var limit: Int = 3
    var onTap: ((ProactiveSignal) -> Void)?
    var onDismiss: ((ProactiveSignal) -> Void)?

    var body: some View {
        let shown = Array(signals.prefix(limit))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PROACTIVE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if signals.count > limit {
                    Text("+\(signals.count - limit) more")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(shown) { signal in
                row(signal)
            }
        }
        .padding(.vertical, 4)
        .background(
            DS.Surface.chrome,
            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: DS.Stroke.hairline)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("dashboard.proactiveStrip")
    }

    @ViewBuilder
    private func row(_ signal: ProactiveSignal) -> some View {
        Button {
            onTap?(signal)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(color(for: signal.severity))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .lineLimit(1)
                    Text(signal.body)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: icon(for: signal.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
                if onDismiss != nil {
                    Button {
                        onDismiss?(signal)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.6))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                    .accessibilityIdentifier("dashboard.proactiveStrip.dismiss")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.proactiveStrip.row")
    }

    private func color(for severity: ProactiveSignal.Severity) -> Color {
        switch severity {
        case .alert:   return tokens.lossAccent.color
        case .warning: return Color.orange
        case .info:    return tokens.accent.color
        }
    }

    private func icon(for kind: ProactiveSignal.Kind) -> String {
        switch kind {
        case .upcomingBill:   return "calendar.badge.clock"
        case .newRecurring:   return "arrow.triangle.2.circlepath"
        case .anomalousSpend: return "exclamationmark.triangle"
        }
    }
}
