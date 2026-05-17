import SwiftUI
import DesignSystem
import Models
import SynnapseCharts

/// Minimal SwiftUI host for the cash-flow forecast.
///
/// Added 2026-05-17 during the four-branch Copilot integration. The
/// AI++ wedge shipped `ForecastViewModel` + reducer without a view;
/// this is the minimum-viable surface for the INTELLIGENCE sidebar
/// row. Paints three blocks: the next-30-days bills total, the list
/// of predicted recurring charges, and a zero-crossing banner when
/// the central estimate dips below zero in the horizon window.
///
/// The full Swift Charts series rendering (with the shaded confidence
/// band) belongs on `FinancePersonalView` per agent 5's manifest; this
/// surface is the standalone "show me the forecast" detail.
@MainActor
public struct ForecastView: View {

    @Bindable private var viewModel: ForecastViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(viewModel: ForecastViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(tokens: tokens)

                // Stat cards, zero-crossing banner, and predicted
                // charges list all read from `viewModel.projection`
                // — a deterministic [[BalanceProjection]] derived
                // from the user's recurring history. Every figure on
                // this surface is a function of the transaction feed,
                // not a hardcoded string.
                if viewModel.projection != nil {
                    summaryRow(tokens: tokens)
                    if let banner = viewModel.projectedZeroBanner {
                        zeroCrossingBanner(text: banner, tokens: tokens)
                    }
                    projectionChartSection(tokens: tokens)
                    predictedCharges(tokens: tokens)
                } else if viewModel.isLoading {
                    loadingState(tokens: tokens)
                } else if let err = viewModel.lastError {
                    errorState(message: err, tokens: tokens)
                } else {
                    emptyState(tokens: tokens)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("intelligence.forecast")
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FORECAST")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text("Next \(viewModel.horizonDays) days")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }

    @ViewBuilder
    private func summaryRow(tokens: TokenSet) -> some View {
        HStack(spacing: 16) {
            statCard(
                label: "Next \(viewModel.horizonDays) days of bills",
                value: formatCurrency(viewModel.nextThirtyDaysBillsTotal),
                tokens: tokens
            )
            statCard(
                label: "Predicted charges",
                value: "\(viewModel.predictedChargesCount)",
                tokens: tokens
            )
        }
    }

    @ViewBuilder
    private func statCard(label: String, value: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.04))
        )
    }

    @ViewBuilder
    private func zeroCrossingBanner(text: String, tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tokens.category(.loans))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.category(.loans).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.category(.loans).opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func projectionChartSection(tokens: TokenSet) -> some View {
        // The Forecast v2 chart sits between the zero-crossing banner
        // and the predicted-charges list. Height is a fixed 280pt so
        // the surface scrolls predictably and the axis ticks have
        // enough room to read without crowding. Agent B replaces the
        // KPI cards above; this slot is owned by Agent A alone.
        VStack(alignment: .leading, spacing: 8) {
            Text("BALANCE PROJECTION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            BalanceProjectionChart(
                historical: viewModel.historicalSeries,
                projection: viewModel.projectionSeries,
                events: chartEvents(),
                zeroCrossing: viewModel.projection?.projectedZeroDate,
                today: viewModel.projection?.today ?? Date()
            )
            .frame(height: 280)
        }
    }

    private func chartEvents() -> [BalanceProjectionEvent] {
        let credits = viewModel.creditEvents.map {
            BalanceProjectionEvent(
                merchant: $0.merchant, amount: $0.amount,
                date: $0.date, kind: .credit
            )
        }
        let debits = viewModel.debitEvents.map {
            BalanceProjectionEvent(
                merchant: $0.merchant, amount: $0.amount,
                date: $0.date, kind: .debit
            )
        }
        return credits + debits
    }

    @ViewBuilder
    private func predictedCharges(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREDICTED CHARGES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            let charges = viewModel.predictedChargesList
            if charges.isEmpty {
                Text("No predicted recurring charges in this window.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            } else {
                ForEach(charges) { flow in
                    flowRow(flow: flow, tokens: tokens)
                }
            }
        }
    }

    @ViewBuilder
    private func flowRow(flow: ScheduledFlow, tokens: TokenSet) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(flow.merchant)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(formatDate(flow.date))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            Text(formatCurrency(flow.amount))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.03))
        )
    }

    @ViewBuilder
    private func loadingState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Projecting your cash flow…")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func errorState(message: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Forecast unavailable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func emptyState(tokens: TokenSet) -> some View {
        Text("No forecast yet. Choose an account to project its cash flow forward.")
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(tokens.foregroundSecondary.color)
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}
