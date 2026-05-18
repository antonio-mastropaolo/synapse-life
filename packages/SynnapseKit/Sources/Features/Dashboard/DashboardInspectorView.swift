import SwiftUI
import DesignSystem

/// Right-column inspector for the Dashboard.
///
/// Stack (top → bottom):
///   1. Goals card (kept from the original Copilot layout)
///   2. Spending pulse (today vs typical)
///   3. Anomaly mini-list (top-3 flagged)
///   4. AI suggestion (single sentence)
///
/// The original "Net this month" card was retired here — that figure
/// now lives in the NET THIS WEEK hero card up top, so duplicating it
/// in the inspector reads as noise. macOS + iPad regular render this
/// at 280pt fixed width; iPhone collapses it below the list.
@MainActor
struct DashboardInspectorView: View {

    let widgetState: WidgetState
    let goalsCurrency: String

    var openGoals: (() -> Void)?
    var openAnomalyExplainer: ((String) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                goalsCard(tokens: tokens)
                DashboardSpendingPulseCard(
                    state: widgetState.spendingPulse,
                    currency: goalsCurrency
                )
                DashboardAnomalyMiniList(
                    anomalies: widgetState.anomalies,
                    openAnomalyExplainer: openAnomalyExplainer
                )
                DashboardAISuggestionCard(
                    narration: widgetState.aiSuggestion
                )
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tokens.background.color)
    }

    // MARK: - Goals card (kept)

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
}
