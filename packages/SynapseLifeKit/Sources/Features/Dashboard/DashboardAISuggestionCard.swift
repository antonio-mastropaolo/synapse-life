import SwiftUI
import DesignSystem

/// Inspector card: a single AI-narrated sentence with an optional CTA.
///
/// The integrator wires this to `DigestReducer`; when the provider
/// returns nil the card collapses (no stub copy, no "thinking…"
/// placeholder — the surface stays quiet until there's something
/// worth saying).
///
/// Visual: subtle gradient border so the card reads as "different"
/// from the regular hairline cards without screaming AI. No
/// shimmering, no sparkles. Animation gated by Reduce Motion.
@MainActor
struct DashboardAISuggestionCard: View {

    let narration: DashboardWidgetReducer.AINarration?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Double = 0

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        if let narration {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ASSISTANT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Spacer()
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.accent.color)
                }
                Text(narration.sentence)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                if let cta = narration.cta {
                    Text(cta)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.accent.color)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DS.Surface.card,
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(borderGradient(tokens: tokens), lineWidth: 1)
            )
            .elevation(DS.Elevation.card)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Assistant: \(narration.sentence)" +
                (narration.cta.map { ". Action: \($0)" } ?? "")
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        } else {
            EmptyView()
        }
    }

    /// Soft accent-tinted border. Animates a slow phase rotation
    /// when motion is allowed; otherwise renders as a static gradient.
    private func borderGradient(tokens: TokenSet) -> LinearGradient {
        let start: UnitPoint
        let end: UnitPoint
        if reduceMotion {
            start = .topLeading
            end = .bottomTrailing
        } else {
            let p = phase
            start = UnitPoint(x: p, y: 0)
            end = UnitPoint(x: 1 - p, y: 1)
        }
        return LinearGradient(
            colors: [
                tokens.accent.color.opacity(0.55),
                tokens.accent.color.opacity(0.10),
                tokens.accent.color.opacity(0.55)
            ],
            startPoint: start,
            endPoint: end
        )
    }
}
