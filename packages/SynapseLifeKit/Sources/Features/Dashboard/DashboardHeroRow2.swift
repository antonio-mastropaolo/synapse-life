import SwiftUI
import DesignSystem
import Models

/// Second row of four hero cards on the Dashboard. Stacks beneath
/// `DashboardHeroRow` so the dashboard opens with an 8-tile glance
/// instead of 4. Cards in this row carry slower-moving signal than
/// the top row (the top row is week-shaped: NET / UNREVIEWED / TOP
/// CATEGORY / NEXT BILL; this row is monthly + cross-surface):
///
///   [ TODAY | THIS MONTH | GOALS | MEMBERSHIPS ]
///
/// Visual treatment mirrors `DashboardHeroRow.heroCard` exactly so the
/// two rows read as one block — same 110pt height, same 10pt corner
/// radius, same hairline border, same stagger-in animation.
@MainActor
struct DashboardHeroRow2: View {

    let widgetState: WidgetState
    let currency: String
    let monthSpendTotal: Decimal
    let monthDayCount: Int
    let monthSparkline: [Double]

    /// Optional cross-surface stores. When present, the Goals tile and
    /// Memberships tile read real numbers; nil falls back to a SAMPLE
    /// chip + canned figures so the dashboard never paints an empty
    /// card just because demo mode skipped a wire-up.
    var goalsStore: GoalsStore?
    var membershipsStore: MembershipsStore?

    var openGoals: (() -> Void)?
    var openMemberships: (() -> Void)?
    var openSpending: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-card mount flags. Stagger matches the top row's 60ms
    /// cascade so the two rows arrive feeling like one wave.
    @State private var hasAppeared: [Bool] = Array(repeating: false, count: 4)

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            todayCard(tokens: tokens)
            monthCard(tokens: tokens)
            goalsCard(tokens: tokens)
            membershipsCard(tokens: tokens)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .onAppear { runStagger() }
    }

    // MARK: - Cards

    private func todayCard(tokens: TokenSet) -> some View {
        let pulse = widgetState.spendingPulse
        let todayDouble = (pulse.today as NSDecimalNumber).doubleValue
        let typicalDouble = (pulse.typical as NSDecimalNumber).doubleValue
        let delta = todayDouble - typicalDouble
        let tone: Color = delta > 5
            ? Color(red: 1.00, green: 0.69, blue: 0.22)
            : Color(red: 0.34, green: 0.78, blue: 0.50)
        return heroCard(index: 0, tokens: tokens, onTap: openSpending) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                eyebrow(text: "TODAY", tokens: tokens)
                Text(formatCompact(pulse.today))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
                pulseBar(ratio: pulse.ratio, tone: tone, tokens: tokens)
                Text("vs $\(Int(typicalDouble)) typical")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    private func monthCard(tokens: TokenSet) -> some View {
        heroCard(index: 1, tokens: tokens, onTap: nil) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                eyebrow(text: "THIS MONTH", tokens: tokens)
                Text(formatCompact(monthSpendTotal))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
                miniBars(values: monthSparkline,
                         tint: Color(red: 0.27, green: 0.83, blue: 0.89),
                         tokens: tokens)
                Text("over \(monthDayCount) day\(monthDayCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    private func goalsCard(tokens: TokenSet) -> some View {
        let active = goalsStore?.goals.filter { $0.status == .active } ?? []
        let lastResults = active.compactMap { $0.weeklyResults.last }
        let hits = lastResults.filter { $0.outcome == .hit }.count
        let total = active.count
        let isSample = goalsStore == nil
        return heroCard(index: 2, tokens: tokens, onTap: openGoals) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: 6) {
                    eyebrow(text: "GOALS", tokens: tokens)
                    if isSample { sampleChip }
                }
                if total == 0 {
                    Text("None yet")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(hits)")
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.34, green: 0.78, blue: 0.50))
                            .monospacedDigit()
                        Text("/ \(total)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                            .monospacedDigit()
                    }
                }
                progressRing(progress: total == 0 ? 0 : Double(hits) / Double(total),
                             tokens: tokens)
                Text(total == 0
                     ? "Apply an AI tip to start"
                     : (hits == total ? "All hit this week" : "\(total - hits) missed"))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    private func membershipsCard(tokens: TokenSet) -> some View {
        let memberships = membershipsStore?.memberships ?? []
        let monthly = memberships.reduce(Decimal.zero) { $0 + $1.monthlyCost }
        let count = memberships.count
        let isSample = membershipsStore == nil
        return heroCard(index: 3, tokens: tokens, onTap: openMemberships) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: 6) {
                    eyebrow(text: "MEMBERSHIPS", tokens: tokens)
                    if isSample { sampleChip }
                }
                Text(formatCompact(monthly))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()
                membershipPills(memberships: memberships, tokens: tokens)
                Text("\(count) service\(count == 1 ? "" : "s") · per month")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    // MARK: - Shared chrome (mirrors DashboardHeroRow.heroCard)

    @ViewBuilder
    private func heroCard<Content: View>(
        index: Int,
        tokens: TokenSet,
        onTap: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let appeared = reduceMotion ? true : hasAppeared[index]
        Group {
            if let onTap {
                Button(action: onTap) {
                    content()
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .padding(DS.Spacing.md)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                content()
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                    .padding(DS.Spacing.md)
            }
        }
        .background(
            DS.Surface.card,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: DS.Stroke.hairline)
        )
        .elevation(DS.Elevation.card)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    private func eyebrow(text: String, tokens: TokenSet) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(tokens.foregroundSecondary.color)
    }

    private var sampleChip: some View {
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

    // MARK: - Micro-charts

    private func pulseBar(ratio: Double, tone: Color, tokens: TokenSet) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tone.opacity(0.18))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tone)
                    .frame(width: max(4, geo.size.width * CGFloat(min(max(ratio, 0), 1))), height: 6)
            }
        }
        .frame(height: 6)
    }

    private func miniBars(values: [Double], tint: Color, tokens: TokenSet) -> some View {
        let safe = values.isEmpty ? [0.0] : values
        let peak = safe.max() ?? 1
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(safe.enumerated()), id: \.offset) { _, v in
                let h = max(2, CGFloat(min(v / max(peak, 1), 1.0)) * 18)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint.opacity(0.85))
                    .frame(height: h)
            }
        }
        .frame(height: 18)
    }

    private func progressRing(progress: Double, tokens: TokenSet) -> some View {
        let accent = Color(red: 1.00, green: 0.69, blue: 0.22)
        let p = max(0.04, min(progress, 1.0))
        return HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.20), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
            Spacer()
        }
        .frame(height: 18)
    }

    private func membershipPills(memberships: [Membership], tokens: TokenSet) -> some View {
        // Top 4 logos packed tight, like Apple's app stack indicator.
        let top = memberships.prefix(4)
        return HStack(spacing: -6) {
            ForEach(Array(top.enumerated()), id: \.offset) { _, m in
                Circle()
                    .fill(tokens.surface.color)
                    .overlay(
                        Text(String(m.merchant.prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                    )
                    .overlay(
                        Circle().stroke(tokens.foregroundSecondary.color.opacity(0.30), lineWidth: 1)
                    )
                    .frame(width: 18, height: 18)
            }
            Spacer()
        }
        .frame(height: 18)
    }

    // MARK: - Helpers

    private func formatCompact(_ amount: Decimal) -> String {
        let d = (amount as NSDecimalNumber).doubleValue
        if d >= 1000 { return String(format: "$%.1fK", d / 1000) }
        return String(format: "$%.0f", d)
    }

    private func runStagger() {
        guard !reduceMotion else {
            hasAppeared = Array(repeating: true, count: 4)
            return
        }
        for index in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.060 * Double(index)) {
                if index < hasAppeared.count {
                    withAnimation(DS.Motion.snappy) {
                        hasAppeared[index] = true
                    }
                }
            }
        }
    }
}
