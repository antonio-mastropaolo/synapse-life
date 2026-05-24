import SwiftUI
import DesignSystem
import Models

/// Per-position drill-down for the Investments tab. Renders ticker hero,
/// market value, unrealized P/L (signed), and quantity/price metadata.
///
/// We deliberately do NOT chart price history here — the existing
/// `InvestmentPosition` model does not carry a series; a future iteration
/// can wire a per-position history endpoint and add a Swift Charts line
/// view above the metadata block.
@MainActor
struct PositionDetailView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let position: InvestmentPosition

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let pnl = position.unrealizedPnL ?? .zero
        let isGain = pnl >= .zero
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(position.ticker ?? "—")
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(position.name ?? position.accountName)
                        .font(tokens.tickerFont(size: 12))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Market value")
                        .font(tokens.tickerFont(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text(position.value.formatted(.currency(code: position.currency)))
                        .font(.system(size: 38, weight: .medium, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    HStack(spacing: 8) {
                        Text("Unrealized")
                            .font(tokens.tickerFont(size: 10, weight: .semibold))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                        Text(pnl.formatted(.currency(code: position.currency)))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(isGain ? tokens.gainAccent.color : tokens.lossAccent.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(tokens.surface.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 10) {
                    DetailRow(label: "Quantity",
                              value: position.quantity.formatted(.number.precision(.fractionLength(0...4))))
                    DetailRow(label: "Price",
                              value: position.price.formatted(.currency(code: position.currency)))
                    DetailRow(label: "Kind",
                              value: position.kind.rawValue.capitalized)
                    DetailRow(label: "Account",
                              value: position.accountName)
                }
                .padding(16)
                .background(tokens.surface.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(tokens.background.color.ignoresSafeArea())
        .navigationTitle(position.ticker ?? "Position")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String
    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack {
            Text(label)
                .font(tokens.tickerFont(size: 11, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .multilineTextAlignment(.trailing)
        }
    }
}
