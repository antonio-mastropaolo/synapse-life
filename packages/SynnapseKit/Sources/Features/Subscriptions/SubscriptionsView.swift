import SwiftUI
import DesignSystem
import Models

/// Subscriptions surface — replaces the `ComingSoonView` stub that
/// shipped in c0ff459. Renders the detected `[DetectedSubscription]`
/// list with monthly + yearly totals at the top, a grid of cards on
/// macOS (one row per merchant on iOS), and a placeholder cancel
/// instruction sheet behind a per-row button.
///
/// The grid card carries an SF Symbol per merchant, the cadence
/// label, the monthly + yearly amounts, and the last-charged /
/// next-expected dates so the user can answer "what is costing me
/// and when does the next hit land".
@MainActor
public struct SubscriptionsView: View {

    @Bindable private var viewModel: SubscriptionsViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var cancelSheetMerchant: String?

    public init(viewModel: SubscriptionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(tokens: tokens)
                if viewModel.subscriptions.isEmpty {
                    emptyState(tokens: tokens)
                } else {
                    grid(tokens: tokens)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("more.subscriptions")
        .sheet(item: cancelSheetBinding) { merchant in
            cancelSheet(merchant: merchant.name, tokens: tokens)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUBSCRIPTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCurrency(viewModel.monthlyTotal))
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .monospacedDigit()
                    Text("per month".uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCurrency(viewModel.yearlyTotal))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .monospacedDigit()
                    Text("per year".uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.count)")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .monospacedDigit()
                    Text("detected".uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Spacer()
            }
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private func grid(tokens: TokenSet) -> some View {
        let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 12)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(viewModel.subscriptions) { sub in
                card(subscription: sub, tokens: tokens)
            }
        }
    }

    @ViewBuilder
    private func card(subscription sub: DetectedSubscription, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tokens.category(.subscriptions).opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: MerchantIconResolver.symbol(for: sub.merchant))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tokens.category(.subscriptions))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(sub.merchant)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(sub.cadenceLabel.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatCurrency(sub.monthlyEquivalent))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
                Text("/mo")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                if sub.cadenceDays != 30 {
                    Text("· \(formatCurrency(sub.amount))/\(rawCadenceSuffix(sub.cadenceDays))")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                row(label: "Last charged", value: formatDate(sub.lastCharged), tokens: tokens)
                row(label: "Next expected", value: formatDate(sub.nextExpected), tokens: tokens)
            }

            Button {
                cancelSheetMerchant = sub.merchant
            } label: {
                Text("Cancel".uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(tokens.foregroundSecondary.color.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("subscription.cancel.\(sub.merchant.lowercased())")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundPrimary.color.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(label: String, value: String, tokens: TokenSet) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
        }
    }

    // MARK: - Empty

    @ViewBuilder
    private func emptyState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No subscriptions detected yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("As your transactions accumulate, recurring SaaS and streaming charges will show up here.")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    // MARK: - Cancel sheet

    private struct SheetMerchant: Identifiable {
        let id = UUID()
        let name: String
    }

    private var cancelSheetBinding: Binding<SheetMerchant?> {
        Binding(
            get: { cancelSheetMerchant.map { SheetMerchant(name: $0) } },
            set: { cancelSheetMerchant = $0?.name }
        )
    }

    @ViewBuilder
    private func cancelSheet(merchant: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cancel \(merchant)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Visit \(merchant)'s account page to cancel. Synnapse can't cancel subscriptions on your behalf — but it can remind you the day before the next charge lands.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack {
                Spacer()
                Button("Close") { cancelSheetMerchant = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
        .background(tokens.background.color)
    }

    // MARK: - Formatting

    private func rawCadenceSuffix(_ days: Int) -> String {
        switch days {
        case 90:  return "qtr"
        case 365: return "yr"
        default:  return "\(days)d"
        }
    }

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
