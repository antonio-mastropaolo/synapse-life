import SwiftUI
import DesignSystem

/// Placeholder surface for tabs / drill-downs whose owning agent
/// has not yet shipped. Intentionally honest: a one-line headline,
/// a one-line subtitle, and the SF Symbol of the eventual feature.
///
/// We do NOT show a progress spinner or a fake skeleton — those
/// would imply "loading", and a user who pulls-to-refresh would
/// expect a result. "Coming soon" with a clear glyph is the
/// minimum-deception affordance and tracks the project's
/// no-half-measures discipline.
@MainActor
struct ComingSoonView: View {

    let title: String
    let subtitle: String
    let symbol: String

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(tokens.accent.color)
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(subtitle)
                .font(tokens.tickerFont(size: 12))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("COMING SOON")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tokens.foregroundSecondary.color.opacity(0.45), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background.color)
    }
}
