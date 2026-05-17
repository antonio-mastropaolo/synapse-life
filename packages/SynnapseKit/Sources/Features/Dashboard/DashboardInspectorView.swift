import SwiftUI
import DesignSystem

/// Right-column inspector for the Dashboard. Matches the Copilot
/// screenshot — a Goals card on top and a "Net this month" card
/// below. The inspector is rendered only on regular-width Apple
/// platforms (macOS + iPad regular); iPhone hides it and surfaces
/// the same data through the More tab.
@MainActor
struct DashboardInspectorView: View {

    let netThisMonth: Decimal
    let goalsCurrency: String

    /// Closure for the "Goals" card chrome → the caller wires this
    /// to the macOS sidebar's Goals destination (or the iOS More
    /// tab) when the integrator lands the routes. Optional so the
    /// dashboard renders standalone.
    var openGoals: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 12) {
            goalsCard(tokens: tokens)
            netCard(tokens: tokens)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tokens.background.color)
    }

    // MARK: - Cards

    @ViewBuilder
    private func goalsCard(tokens: TokenSet) -> some View {
        Button {
            openGoals?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GOALS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Text("$0")
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("saved in May")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tokens.surface.color)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goals, $0 saved in May")
    }

    @ViewBuilder
    private func netCard(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NET THIS MONTH")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text("CASH-FLOW")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Text(formattedNet)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(netColor(tokens: tokens))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Net this month, \(formattedNet)")
    }

    // MARK: - Formatting

    private var formattedNet: String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = goalsCurrency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        let abs = netThisMonth.magnitude
        let body = nf.string(from: abs as NSDecimalNumber) ?? "$0.00"
        if netThisMonth < 0 { return "-\(body)" }
        return body
    }

    private func netColor(tokens: TokenSet) -> Color {
        if netThisMonth > 0 { return tokens.gainAccent.color }
        if netThisMonth < 0 { return tokens.lossAccent.color }
        return tokens.foregroundPrimary.color
    }
}
