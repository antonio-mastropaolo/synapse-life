import SwiftUI
import DesignSystem

/// Rich placeholder for the Goals surface. Stands in until a real
/// Goals data model + VM + persistence land. Renders four sample
/// goals with progress rings, an AI-suggested-goals strip below, and
/// a sticky "Add goal" call-to-action.
///
/// Every figure is obviously a sample (the section header literally
/// says "Sample goals — your real goals will appear here"). The
/// reason this exists rather than a one-liner stub: an empty section
/// reads as "broken" even when it's marked Coming Soon. A populated
/// surface tells the operator what the feature is going to look like
/// and how it will fit the visual rhythm of the rest of the app.
@MainActor
public struct GoalsPlaceholderView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header(tokens: tokens)
                sampleBanner(tokens: tokens)
                goalsGrid(tokens: tokens)
                aiSuggested(tokens: tokens)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
    }

    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goals")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Track what you're saving toward. AI suggests timelines based on your typical monthly surplus.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    private func sampleBanner(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("Sample goals — your real goals will appear here once accounts are connected.")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func goalsGrid(tokens: TokenSet) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Self.sampleGoals) { goal in
                goalCard(goal: goal, tokens: tokens)
            }
        }
    }

    private func goalCard(goal: SampleGoal, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text(goal.name)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                }
                Spacer()
                progressRing(progress: goal.progress, accent: goal.accent)
                    .frame(width: 52, height: 52)
            }

            // Saved vs target.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$\(formatThousands(goal.savedAmount))")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("of $\(formatThousands(goal.targetAmount))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }

            // Monthly + ETA.
            HStack(spacing: 18) {
                miniStat(label: "Monthly", value: "$\(formatThousands(goal.monthlyContribution))", tokens: tokens)
                miniStat(label: "ETA",     value: goal.eta, tokens: tokens)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func miniStat(label: String, value: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }

    private func progressRing(progress: Double, accent: Color) -> some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1.0)))
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
        }
    }

    private func aiSuggested(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.22))
                Text("AI-SUGGESTED GOALS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.aiSuggestions) { s in
                    suggestionRow(s, tokens: tokens)
                    Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                }
            }
        }
    }

    private func suggestionRow(_ s: SampleSuggestion, tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: s.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(s.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(s.rationale)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(2)
            }
            Spacer()
            Text("$\(formatThousands(s.suggestedTarget))")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Sample data

    private struct SampleGoal: Identifiable {
        let id = UUID()
        let title: String
        let name: String
        let savedAmount: Int
        let targetAmount: Int
        let monthlyContribution: Int
        let eta: String
        let accent: Color
        var progress: Double { Double(savedAmount) / Double(max(targetAmount, 1)) }
    }

    private static let sampleGoals: [SampleGoal] = [
        SampleGoal(title: "Sample · safety", name: "Emergency Fund",
                   savedAmount: 3500, targetAmount: 10000,
                   monthlyContribution: 500, eta: "Mar 2027",
                   accent: Color(red: 0.27, green: 0.83, blue: 0.89)),
        SampleGoal(title: "Sample · travel", name: "Vacation Fund",
                   savedAmount: 1800, targetAmount: 3000,
                   monthlyContribution: 250, eta: "Oct 2026",
                   accent: Color(red: 1.00, green: 0.69, blue: 0.22)),
        SampleGoal(title: "Sample · gear", name: "New Laptop",
                   savedAmount: 1600, targetAmount: 2000,
                   monthlyContribution: 300, eta: "Aug 2026",
                   accent: Color(red: 0.94, green: 0.33, blue: 0.56)),
        SampleGoal(title: "Sample · home", name: "House Down Payment",
                   savedAmount: 6000, targetAmount: 50000,
                   monthlyContribution: 800, eta: "Jul 2030",
                   accent: Color(red: 0.34, green: 0.78, blue: 0.50))
    ]

    private struct SampleSuggestion: Identifiable {
        let id = UUID()
        let name: String
        let rationale: String
        let suggestedTarget: Int
        let icon: String
        let accent: Color
    }

    private static let aiSuggestions: [SampleSuggestion] = [
        SampleSuggestion(
            name: "Quarterly Tax Reserve",
            rationale: "You receive freelance income — a tax reserve avoids the April crunch.",
            suggestedTarget: 4500,
            icon: "doc.text.fill",
            accent: Color(red: 1.00, green: 0.69, blue: 0.22)
        ),
        SampleSuggestion(
            name: "Annual Subscription Refresh",
            rationale: "You spend $20–25/mo on recurring subscriptions. Pre-funding the year removes friction.",
            suggestedTarget: 280,
            icon: "arrow.clockwise.circle.fill",
            accent: Color(red: 0.27, green: 0.83, blue: 0.89)
        )
    ]

    private func formatThousands(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
