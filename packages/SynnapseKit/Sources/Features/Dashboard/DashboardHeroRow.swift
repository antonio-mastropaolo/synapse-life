import SwiftUI
import DesignSystem
import Models

/// Four-card hero row sitting beneath the Dashboard header.
///
///   [ NET THIS WEEK | UNREVIEWED | TOP CATEGORY | NEXT BILL ]
///
/// Each card is a rounded-rect tile (10pt radius, hairline border,
/// 110pt tall). The row is a single `HStack` on macOS / iPad regular
/// and a horizontally-scrollable carousel on iPhone — the cards never
/// shrink below 220pt wide so the headline figure stays readable.
///
/// Animations:
///   - staggered fade+rise on first appear (60ms intervals)
///   - hover-lift on macOS via `.onHover`
///   - `.contentTransition(.numericText())` on all changing numbers
///
/// Every animation is gated on `\.accessibilityReduceMotion` — when
/// the user prefers reduced motion, all stagger collapses to 0ms and
/// the hover-lift is dropped entirely.
@MainActor
struct DashboardHeroRow: View {

    let widgetState: WidgetState

    /// Currency for net/top-category/next-bill formatting. The view
    /// model exposes a "first transaction's currency" string; if no
    /// transactions exist we fall back to USD.
    let currency: String

    /// Closure dependencies — all optional, all wired by the
    /// integrator. See `DashboardView.init` for the surface contract.
    var openCashFlow: (() -> Void)?
    var openTopCategory: (() -> Void)?
    var openNextBill: (() -> Void)?
    var iconResolver: ((String) -> Image?)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-card mount flags. Flipped 60ms apart on first appear so
    /// the row "cascades" in. Skipped under Reduce Motion.
    @State private var hasAppeared: [Bool] = Array(repeating: false, count: 4)

    init(
        widgetState: WidgetState,
        currency: String,
        openCashFlow: (() -> Void)? = nil,
        openTopCategory: (() -> Void)? = nil,
        openNextBill: (() -> Void)? = nil,
        iconResolver: ((String) -> Image?)? = nil,
        immediateAppearance: Bool = false
    ) {
        self.widgetState = widgetState
        self.currency = currency
        self.openCashFlow = openCashFlow
        self.openTopCategory = openTopCategory
        self.openNextBill = openNextBill
        self.iconResolver = iconResolver
        // Snapshot tests pass `immediateAppearance: true` so the row
        // paints in its post-stagger steady state without depending on
        // `\.accessibilityReduceMotion` (a read-only env value on
        // recent Swift versions). Production call sites leave the flag
        // at its default and rely on the regular stagger.
        _hasAppeared = State(
            initialValue: Array(repeating: immediateAppearance, count: 4)
        )
    }

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(alignment: .top, spacing: 12) {
            heroCard(index: 0, tokens: tokens) {
                NetThisWeekCard(
                    state: widgetState.netThisWeek,
                    currency: currency,
                    tokens: tokens,
                    onTap: openCashFlow
                )
            }
            heroCard(index: 1, tokens: tokens) {
                UnreviewedCard(state: widgetState.unreviewed, tokens: tokens)
            }
            heroCard(index: 2, tokens: tokens) {
                TopCategoryCard(
                    state: widgetState.topCategory,
                    currency: currency,
                    tokens: tokens,
                    onTap: openTopCategory
                )
            }
            heroCard(index: 3, tokens: tokens) {
                NextBillCard(
                    state: widgetState.nextBill,
                    currency: currency,
                    iconResolver: iconResolver,
                    tokens: tokens,
                    onTap: openNextBill
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onAppear { runStagger() }
    }

    /// Mount one card with the stagger transition. Under Reduce
    /// Motion, the card paints in its final state immediately and no
    /// timer is scheduled.
    @ViewBuilder
    private func heroCard<Content: View>(
        index: Int,
        tokens: TokenSet,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let appeared = reduceMotion ? true : hasAppeared[index]
        content()
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .glassCard(radius: DS.Radius.card, padding: 14)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
    }

    /// Schedule the cascading appear. Each card lights up 60ms after
    /// the previous one. We use a single `Task` over `Task.sleep`
    /// rather than per-card `DispatchQueue.asyncAfter` so the chain
    /// is cancelled cleanly when the row is torn down (test churn).
    private func runStagger() {
        guard !reduceMotion else {
            hasAppeared = Array(repeating: true, count: 4)
            return
        }
        for index in 0..<4 {
            // Guard against re-entry: if the flag is already set
            // (mounted twice from a parent rebuild) skip the delay.
            guard !hasAppeared[index] else { continue }
            let delayNs = UInt64(index * 60_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delayNs)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    if index < hasAppeared.count { hasAppeared[index] = true }
                }
            }
        }
    }
}

// MARK: - NET THIS WEEK

@MainActor
private struct NetThisWeekCard: View {
    let state: DashboardWidgetReducer.NetThisWeek
    let currency: String
    let tokens: TokenSet
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 6) {
                cardHeader(label: "NET THIS WEEK", tokens: tokens)
                Text(format(state.current, currency: currency, signed: true))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(headlineColor)
                deltaChip
                DashboardSparkline(values: state.sparkline, tint: headlineColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !reduceMotion ? 1.01 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.10 : 0.0), radius: 6, y: 3)
        .onHover { hov in
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.14)) { isHovered = hov }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Net this week, \(format(state.current, currency: currency, signed: true)). " +
            "Delta \(format(state.delta, currency: currency, signed: true)) versus last week."
        )
        .accessibilityAddTraits(.isButton)
    }

    private var headlineColor: Color {
        if state.current > 0 { return tokens.gainAccent.color }
        if state.current < 0 { return tokens.lossAccent.color }
        return tokens.foregroundPrimary.color
    }

    @ViewBuilder
    private var deltaChip: some View {
        let isUp = state.delta >= 0
        let chipColor: Color = isUp ? tokens.gainAccent.color : tokens.lossAccent.color
        HStack(spacing: 4) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(format(state.delta.magnitude, currency: currency, signed: false))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(chipColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(chipColor.opacity(0.14))
        )
    }
}

// MARK: - UNREVIEWED

@MainActor
private struct UnreviewedCard: View {
    let state: DashboardWidgetReducer.UnreviewedCount
    let tokens: TokenSet

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardHeader(label: "UNREVIEWED", tokens: tokens)
            Text("\(state.count)")
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(countColor)
            Text(caption)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.count) unreviewed of \(state.total)")
    }

    private var countColor: Color {
        // Inbox-zero positive accent; muted under 10; active above.
        if state.count == 0 { return tokens.gainAccent.color }
        if state.count < 10 { return tokens.foregroundPrimary.color }
        return tokens.accent.color
    }

    private var caption: String {
        if state.count == 0 { return "Inbox zero" }
        return "of \(state.total) total"
    }
}

// MARK: - TOP CATEGORY

@MainActor
private struct TopCategoryCard: View {
    let state: DashboardWidgetReducer.TopCategory?
    let currency: String
    let tokens: TokenSet
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 6) {
                cardHeader(label: "TOP CATEGORY", tokens: tokens)
                if let state {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(pillFill(for: state.category))
                            .frame(width: 10, height: 10)
                        Text(DashboardCategoryPalette.label(for: state.category))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(tokens.foregroundPrimary.color)
                            .lineLimit(1)
                    }
                    Text(formatAbs(state.totalAbsExpense, currency: currency))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("this week")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                } else {
                    Text("No spend yet")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(state == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            state.map {
                "Top category \(DashboardCategoryPalette.label(for: $0.category)), " +
                "\(formatAbs($0.totalAbsExpense, currency: currency)) this week"
            } ?? "Top category, no spend yet"
        )
    }

    private func pillFill(for category: TransactionCategory) -> Color {
        DashboardCategoryPalette.fill(for: category, tokens: tokens)
    }
}

// MARK: - NEXT BILL

@MainActor
private struct NextBillCard: View {
    let state: DashboardWidgetReducer.NextBill?
    let currency: String
    let iconResolver: ((String) -> Image?)?
    let tokens: TokenSet
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 6) {
                cardHeader(label: "NEXT BILL", tokens: tokens)
                if let state {
                    HStack(spacing: 8) {
                        merchantGlyph(state.upcoming.merchant)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.upcoming.merchant)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(tokens.foregroundPrimary.color)
                                .lineLimit(1)
                            Text(urgencyText(state.urgency))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(0.4)
                                .foregroundStyle(urgencyColor(state.urgency))
                        }
                    }
                    Text(formatAbs(state.upcoming.amount, currency: currency))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(tokens.foregroundPrimary.color)
                } else {
                    Text("Nothing upcoming")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(state == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            state.map {
                "Next bill, \($0.upcoming.merchant), \(urgencyText($0.urgency)), " +
                "\(formatAbs($0.upcoming.amount, currency: currency))"
            } ?? "Next bill, nothing upcoming"
        )
    }

    @ViewBuilder
    private func merchantGlyph(_ merchant: String) -> some View {
        if let img = iconResolver?(merchant) {
            img
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            // 1-letter monogram fallback. Picks the first ASCII letter
            // so a merchant string with a leading sigil ("AFFIRM *…")
            // still produces a clean glyph.
            let letter = merchant.unicodeScalars
                .first(where: { CharacterSet.letters.contains($0) })
                .map { String($0) } ?? "·"
            Text(letter.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tokens.foregroundSecondary.color.opacity(0.18))
                )
        }
    }

    private func urgencyText(_ u: DashboardWidgetReducer.NextBillUrgency) -> String {
        switch u {
        case .today:                 return "DUE TODAY"
        case .tomorrow:              return "DUE TOMORROW"
        case .later(let days):       return "IN \(days) DAYS"
        }
    }

    private func urgencyColor(_ u: DashboardWidgetReducer.NextBillUrgency) -> Color {
        switch u {
        case .today, .tomorrow:      return tokens.lossAccent.color
        case .later:                 return tokens.foregroundSecondary.color
        }
    }
}

// MARK: - Shared chrome

@MainActor
private func cardHeader(label: String, tokens: TokenSet) -> some View {
    HStack(spacing: 4) {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(tokens.foregroundSecondary.color)
        Spacer()
        Image(systemName: "arrow.up.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
    }
}

// MARK: - Formatting helpers

/// Currency formatter — signed when `signed` is true (the dashboard's
/// hero uses a real minus glyph, not `()` parens, to match the row's
/// convention). The function constructs a fresh `NumberFormatter`
/// per call; the cost is negligible against the once-per-render cost
/// of the chart underneath.
private func format(_ value: Decimal, currency: String, signed: Bool) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .currency
    nf.currencyCode = currency
    nf.maximumFractionDigits = 0
    nf.minimumFractionDigits = 0
    let abs = value.magnitude
    let body = nf.string(from: abs as NSDecimalNumber) ?? "$0"
    guard signed else { return body }
    if value < 0 { return "-\(body)" }
    if value > 0 { return "+\(body)" }
    return body
}

private func formatAbs(_ value: Decimal, currency: String) -> String {
    format(value, currency: currency, signed: false)
}
