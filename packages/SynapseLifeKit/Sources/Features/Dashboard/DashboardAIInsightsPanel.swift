import SwiftUI
import DesignSystem

/// Dense AI-driven inspector panel for the Dashboard.
///
/// Replaces the original three sparse cards (single-figure Spending
/// Pulse, single-sentence AI Suggestion, three-row Anomaly mini-list)
/// with four richer cards that fill the right-pane real-estate with
/// substantive content rather than empty rectangles:
///
///   1. **AI This Week** — narrative bullets: 3 insights extracted
///      from the week's transactions. Each bullet has a tone glyph
///      (good / warning / neutral) so the reader can scan at a
///      glance.
///   2. **AI Forecast Watch** — 30-day projection figure, sparkline,
///      zero-crossing date or all-clear, biggest upcoming hit.
///   3. **AI Patterns** — detected behavioural patterns ("you spend
///      3x more on weekends"). 2 lines per pattern: the observation
///      and a one-line "what we'd do".
///   4. **AI Suggests** — 3 actionable recommendations with their
///      dollar impact called out.
///
/// All copy lives inline as sample data while demo mode is on — the
/// strings are obviously placeholder ("Sample Cafe", "Sample BNPL").
/// When live data arrives, the integrator swaps the model in for a
/// reducer-driven `AIInsightsState` without changing the view code.
@MainActor
struct DashboardAIInsightsPanel: View {

    /// Sample mode renders deterministic demo content. The real
    /// integration will pass a populated state in.
    let isDemoData: Bool

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 12) {
            weekStoryCard(tokens: tokens)
            forecastWatchCard(tokens: tokens)
            patternsCard(tokens: tokens)
            suggestionsCard(tokens: tokens)
        }
    }

    // MARK: - 1. AI This Week

    private func weekStoryCard(tokens: TokenSet) -> some View {
        aiCard(tokens: tokens, title: "AI THIS WEEK") {
            VStack(alignment: .leading, spacing: 10) {
                insightRow(
                    tone: .good,
                    text: "Restaurants down 50% vs typical week ($122 → $61).",
                    tokens: tokens
                )
                insightRow(
                    tone: .warning,
                    text: "First BNPL charge in 8 weeks: $125.78 on Tuesday.",
                    tokens: tokens
                )
                insightRow(
                    tone: .neutral,
                    text: "Income arrived as expected ($3,460).",
                    tokens: tokens
                )
            }
        }
    }

    // MARK: - 2. AI Forecast Watch

    private func forecastWatchCard(tokens: TokenSet) -> some View {
        aiCard(tokens: tokens, title: "AI FORECAST · 30 DAYS") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("$2,184")
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("projected")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }

                forecastSparkline(
                    points: Self.demoForecast,
                    accent: Color(red: 0.27, green: 0.83, blue: 0.89),
                    background: tokens.foregroundSecondary.color.opacity(0.10)
                )
                .frame(height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    forecastLine(
                        icon: "checkmark.shield.fill",
                        tint: Color(red: 0.34, green: 0.78, blue: 0.50),
                        text: "Balance stays positive through Jun 17.",
                        tokens: tokens
                    )
                    forecastLine(
                        icon: "calendar.badge.clock",
                        tint: Color(red: 1.00, green: 0.69, blue: 0.22),
                        text: "Biggest upcoming hit: Sample BNPL Payment · $340 on May 30.",
                        tokens: tokens
                    )
                }
            }
        }
    }

    private func forecastLine(icon: String, tint: Color, text: String, tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, alignment: .leading)
            Text(text)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func forecastSparkline(points: [Double], accent: Color, background: Color) -> some View {
        GeometryReader { geo in
            let minV = points.min() ?? 0
            let maxV = points.max() ?? 1
            let range = max(maxV - minV, 1)
            let step = geo.size.width / CGFloat(max(points.count - 1, 1))
            ZStack(alignment: .leading) {
                Rectangle().fill(background)
                Path { p in
                    for (i, v) in points.enumerated() {
                        let x = CGFloat(i) * step
                        let y = geo.size.height - CGFloat((v - minV) / range) * geo.size.height
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: - 3. AI Patterns

    private func patternsCard(tokens: TokenSet) -> some View {
        aiCard(tokens: tokens, title: "AI PATTERNS") {
            VStack(alignment: .leading, spacing: 12) {
                patternRow(
                    observation: "You spend 3.2× more on weekends than weekdays.",
                    action: "Front-load discretionary buys to Mon–Thu to smooth the curve.",
                    tokens: tokens
                )
                patternRow(
                    observation: "Subscription spend creeping up: +$15/mo since March.",
                    action: "Audit the 3 services you haven't opened in 60+ days.",
                    tokens: tokens
                )
                patternRow(
                    observation: "Sample BNPL charges cluster on Tuesdays.",
                    action: "Move grocery + restaurant runs off Tuesday to avoid the stack.",
                    tokens: tokens
                )
            }
        }
    }

    private func patternRow(observation: String, action: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.94, green: 0.33, blue: 0.56))
                    .frame(width: 14, alignment: .leading)
                Text(observation)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: 14)
                Text(action)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 4. AI Suggests

    private func suggestionsCard(tokens: TokenSet) -> some View {
        aiCard(tokens: tokens, title: "AI SUGGESTS") {
            VStack(alignment: .leading, spacing: 12) {
                suggestionRow(
                    impact: "+$17/mo",
                    title: "Cancel Sample Audio Subscription",
                    rationale: "Unused 60+ days. The next charge posts on May 21.",
                    tone: Color(red: 0.34, green: 0.78, blue: 0.50),
                    tokens: tokens
                )
                suggestionRow(
                    impact: "+$340",
                    title: "Pre-fund the May 30 BNPL bill",
                    rationale: "Move $340 to Sample Checking by May 26 to avoid the cash dip.",
                    tone: Color(red: 1.00, green: 0.69, blue: 0.22),
                    tokens: tokens
                )
                suggestionRow(
                    impact: "+$4,500",
                    title: "Set a Q3 Tax Reserve goal",
                    rationale: "Freelance pattern suggests ~$4.5k owed in Sept estimated payments.",
                    tone: Color(red: 0.27, green: 0.83, blue: 0.89),
                    tokens: tokens
                )
            }
        }
    }

    private func suggestionRow(
        impact: String, title: String, rationale: String,
        tone: Color, tokens: TokenSet
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(impact)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tone)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tone.opacity(0.15))
                    )
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(rationale)
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared chrome

    private enum InsightTone {
        case good, warning, neutral

        var color: Color {
            switch self {
            case .good:    return Color(red: 0.34, green: 0.78, blue: 0.50)
            case .warning: return Color(red: 1.00, green: 0.69, blue: 0.22)
            case .neutral: return Color(red: 0.27, green: 0.83, blue: 0.89)
            }
        }

        var icon: String {
            switch self {
            case .good:    return "arrow.down.right.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .neutral: return "circle.fill"
            }
        }
    }

    private func insightRow(tone: InsightTone, text: String, tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 14, alignment: .leading)
            Text(text)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func aiCard<Content: View>(
        tokens: TokenSet,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.69, blue: 0.22))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if isDemoData {
                    Text("SAMPLE")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.orange.opacity(0.15))
                        )
                }
            }
            content()
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
    }

    private static let demoForecast: [Double] = [
        2400, 2380, 2410, 2350, 2280, 2300, 2250, 2220, 2200, 2150,
        2120, 2080, 2050, 2000, 1980, 1960, 1980, 2000, 2050, 2080,
        2100, 2120, 2150, 2180, 2200, 2210, 2220, 2230, 2200, 2184
    ]
}
