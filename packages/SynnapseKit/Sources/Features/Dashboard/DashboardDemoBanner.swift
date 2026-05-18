import SwiftUI
import DesignSystem

/// Top-of-dashboard banner shown while the app is running on
/// `DashboardDemoData` (no live backend connected). Two jobs:
///
/// 1. Make it unmistakable that the rows below are placeholders — not
///    real spending. Without this banner, a stranger seeing the app
///    over a shoulder might think "Sample Cafe -$14.65" is a real
///    transaction. Loud copy + amber-warning tone removes that risk.
/// 2. Give the operator a one-tap exit to the connect flow. The
///    callback is wired by the integrator (typically opens
///    `RootDestination.settings` or a future Plaid Link surface).
///
/// Hidden entirely when `isDemoData = false`. No state of its own;
/// the parent owns the boolean.
@MainActor
struct DashboardDemoBanner: View {

    let tokens: TokenSet
    /// Override hook — when nil, the banner falls back to the system's
    /// `\.openSettings` action so the button always has somewhere to go.
    /// Tests inject a no-op closure so they can assert the button is
    /// tappable without bringing up a real Settings scene.
    let onConnect: (() -> Void)?

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Showing sample data")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Every transaction below is a placeholder. Connect your accounts to track your real finances.")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                if let onConnect {
                    onConnect()
                } else {
                    #if os(macOS)
                    openSettings()
                    #endif
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Connect accounts")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.85))
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.demoBanner.connect")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.45))
                .frame(height: 1),
            alignment: .bottom
        )
        .accessibilityIdentifier("dashboard.demoBanner")
    }
}
