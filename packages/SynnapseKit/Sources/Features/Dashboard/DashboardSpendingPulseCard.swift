import SwiftUI
import DesignSystem

/// Inspector card: today's spend vs the 7-day typical.
///
/// A single horizontal progress bar paints `ratio` (today / typical,
/// capped at 1) over a muted track. Underneath, the caption reads the
/// raw figures so the user sees the true ratio even when the bar is
/// capped. Both figures are *positive* expense totals.
@MainActor
struct DashboardSpendingPulseCard: View {

    let state: DashboardWidgetReducer.SpendingPulse
    let currency: String

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animatedRatio: CGFloat = 0

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 8) {
            Text("SPENDING PULSE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundSecondary.color)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tokens.foregroundSecondary.color.opacity(0.12))
                    Capsule()
                        .fill(barColor(tokens: tokens))
                        .frame(width: max(0, geo.size.width * animatedRatio))
                }
            }
            .frame(height: 8)

            HStack(spacing: 6) {
                Text("Today \(format(state.today))")
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("·")
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("Typical \(format(state.typical))")
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DS.Surface.card,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: DS.Stroke.hairline)
        )
        .elevation(DS.Elevation.card)
        .onAppear { applyRatio(state.ratio) }
        .onChange(of: state.ratio) { _, newValue in applyRatio(newValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Spending pulse. Today \(format(state.today)). " +
            "Typical \(format(state.typical))."
        )
    }

    private func applyRatio(_ ratio: Double) {
        let cg = CGFloat(min(max(ratio, 0), 1))
        guard !reduceMotion else { animatedRatio = cg; return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            animatedRatio = cg
        }
    }

    private func barColor(tokens: TokenSet) -> Color {
        if state.ratio >= 1.0 { return tokens.lossAccent.color }
        if state.ratio > 0.8 { return tokens.lossAccent.color.opacity(0.7) }
        return tokens.accent.color
    }

    private func format(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = currency
        nf.maximumFractionDigits = 0
        nf.minimumFractionDigits = 0
        return nf.string(from: value as NSDecimalNumber) ?? "$0"
    }
}
