import SwiftUI
import Models
import DesignSystem

/// Inline AI card: the visual signature of a Synapse-Intelligence
/// surface. Card chrome is the same SF Mono typography as every other
/// data row; the only differentiator is a 1pt gradient stroke that
/// reads as "this is computed insight, not raw data" without resorting
/// to a glow.
@MainActor
public struct InsightCard: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let insight: Insight
    var onTap: (() -> Void)? = nil

    public init(insight: Insight, onTap: (() -> Void)? = nil) {
        self.insight = insight
        self.onTap = onTap
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        let accent = strokeColor(tokens: tokens)
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                    Text(kindLabel.uppercased())
                        .font(tokens.tickerFont(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Spacer()
                }
                Text(insight.headline)
                    .font(tokens.tickerFont(size: 12, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(insight.body)
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.surface.color)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        LinearGradient(
                            colors: [accent.opacity(0.75), accent.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kindLabel). \(insight.headline). \(insight.body)")
    }

    private var kindLabel: String {
        switch insight.kind {
        case .anomaly:   return "Anomaly"
        case .forecast:  return "Forecast"
        case .pattern:   return "Pattern"
        case .narration: return "Summary"
        }
    }

    private func strokeColor(tokens: TokenSet) -> Color {
        switch insight.severity {
        case .alert, .warning: return tokens.lossAccent.color
        case .positive:        return tokens.gainAccent.color
        case .info:            return tokens.accent.color
        }
    }
}

/// Horizontal strip of inline insight cards. Used below the hero on
/// every Finance pane.
@MainActor
public struct InsightStrip: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let insights: [Insight]
    let isLoading: Bool
    var onTap: (Insight) -> Void

    public init(
        insights: [Insight],
        isLoading: Bool = false,
        onTap: @escaping (Insight) -> Void = { _ in }
    ) {
        self.insights = insights
        self.isLoading = isLoading
        self.onTap = onTap
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        if insights.isEmpty && isLoading {
            PhosphorPulse()
                .frame(height: 88)
                .frame(maxWidth: .infinity)
                .background(tokens.surface.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if insights.isEmpty {
            // Quiet empty state — no noisy banner; just a one-line note.
            HStack(spacing: 6) {
                Text("SYNAPSE")
                    .font(tokens.tickerFont(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("Nothing notable in the last 7 days.")
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            .padding(.vertical, 8)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(insights) { insight in
                    InsightCard(insight: insight) {
                        onTap(insight)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                }
            }
        }
    }
}

/// Three-dot phosphor-style pulse, used wherever a `ProgressView()`
/// would otherwise paint the wrong identity onto the cockpit.
@MainActor
public struct PhosphorPulse: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var phase: Int = 0

    public init() {}

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { idx in
                Circle()
                    .fill(tokens.foregroundSecondary.color)
                    .opacity(phase == idx ? 1.0 : 0.25)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 240_000_000)
                    phase = (phase + 1) % 3
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Single-line AI narration painted directly under a hero number. Smaller
/// than a card; designed so the user reads it as part of the hero.
@MainActor
public struct NarrationLine: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 6) {
            Text("SYNAPSE")
                .font(tokens.tickerFont(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(tokens.accent.color)
            Text(text)
                .font(tokens.tickerFont(size: 11))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}
