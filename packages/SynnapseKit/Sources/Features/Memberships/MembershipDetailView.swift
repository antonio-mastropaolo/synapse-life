import SwiftUI
import DesignSystem

/// Explode page for a single membership. Mirrors the AI-signal grid
/// pattern that ships on `FinanceTransactionsRedesigned` so the two
/// surfaces read as siblings.
///
/// Sections (top → bottom):
///   1. Hero — 64pt logo, merchant, monthly/annual cost, next-charge
///      date, status pill, close X.
///   2. AI signal tiles (3×2 grid): USAGE PATTERN · PRICE HISTORY ·
///      ALTERNATIVES · AI SUGGESTS · CANCELLATION FRICTION · ANNUAL
///      VS MONTHLY. Each tile is 132pt tall with a tone-colored
///      stroke (matches the FinanceTransactionsRedesigned aiSignalTile).
///   3. Charge history — inline sparkline + last 6 charges.
///   4. Cancellation guide card — friction chip, time chip, numbered
///      steps, "Open cancel page" link if a `cancelUrl` is set.
///   5. Optimization tips list — full set of tips the optimiser
///      emitted for this membership.
@MainActor
struct MembershipDetailView: View {
    let membership: Membership
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                hero(tokens: tokens)
                signalsGrid(tokens: tokens)
                chargeHistorySection(tokens: tokens)
                cancellationCard(tokens: tokens)
                tipsList(tokens: tokens)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("memberships.detail.\(membership.id)")
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 18) {
            MerchantLogoView(
                merchant: membership.merchant,
                fallbackColor: MembershipStatusPill.tone(for: membership.status),
                size: 64
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(membership.merchant)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    MembershipStatusPill(status: membership.status)
                }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    statBlock(label: "Per month",
                              value: formatCurrency(membership.monthlyCost),
                              tokens: tokens,
                              prominent: true)
                    statBlock(label: "Per year",
                              value: formatCurrency(membership.annualCost),
                              tokens: tokens)
                    statBlock(label: "Next charge",
                              value: formatDate(membership.nextExpectedAt),
                              tokens: tokens)
                    statBlock(label: "Cadence",
                              value: cadenceLabel,
                              tokens: tokens)
                }
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(tokens.foregroundPrimary.color.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("memberships.detail.close")
        }
    }

    @ViewBuilder
    private func statBlock(label: String, value: String, tokens: TokenSet, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: prominent ? 22 : 15,
                              weight: .semibold,
                              design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    private var cadenceLabel: String {
        switch membership.cadenceDays {
        case 30: return "Monthly"
        case 90: return "Quarterly"
        case 365: return "Yearly"
        default: return "\(membership.cadenceDays)d"
        }
    }

    // MARK: - AI signals grid

    private struct SignalTile: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tone: Color
    }

    @ViewBuilder
    private func signalsGrid(tokens: TokenSet) -> some View {
        let cols = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        let tiles = buildSignals()
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(tiles) { t in
                signalTile(t, tokens: tokens)
            }
        }
    }

    @ViewBuilder
    private func signalTile(_ t: SignalTile, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: t.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.tone)
                Text(t.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            Text(t.detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(t.tone.opacity(0.30), lineWidth: 1)
        )
    }

    private func buildSignals() -> [SignalTile] {
        let good   = Color(red: 0.34, green: 0.78, blue: 0.50)
        let warn   = Color(red: 1.00, green: 0.69, blue: 0.22)
        let neut   = Color(red: 0.27, green: 0.83, blue: 0.89)
        let alert  = Color(red: 0.94, green: 0.33, blue: 0.56)

        // USAGE PATTERN — derived from status + occurrence count.
        let usage: SignalTile = {
            switch membership.status {
            case .unused:
                return SignalTile(
                    icon: "moon.zzz",
                    title: "Usage pattern",
                    detail: "Low engagement signal — \(membership.occurrenceCount) consecutive charges with no usage trigger we can see. Cancel candidate.",
                    tone: warn
                )
            case .trial:
                return SignalTile(
                    icon: "hourglass",
                    title: "Usage pattern",
                    detail: "Trial — single charge so far. Rollover hits \(formatDate(membership.nextExpectedAt)).",
                    tone: neut
                )
            case .atRisk:
                return SignalTile(
                    icon: "exclamationmark.triangle",
                    title: "Usage pattern",
                    detail: "Charge stream shows volatility — review price history below.",
                    tone: alert
                )
            case .cancelled:
                return SignalTile(
                    icon: "checkmark.circle",
                    title: "Usage pattern",
                    detail: "No charges in over 2× the typical cadence. Looks cancelled — Synapse will reopen if a charge lands.",
                    tone: good
                )
            case .active:
                return SignalTile(
                    icon: "waveform",
                    title: "Usage pattern",
                    detail: "Steady — \(membership.occurrenceCount) charges over the observation window, no drift.",
                    tone: good
                )
            }
        }()

        // PRICE HISTORY — diff first vs last charge.
        let price: SignalTile = {
            guard let first = membership.chargeHistory.first?.amount,
                  let last = membership.chargeHistory.last?.amount,
                  membership.chargeHistory.count >= 2 else {
                return SignalTile(
                    icon: "dollarsign.circle",
                    title: "Price history",
                    detail: "Single charge so far — no price drift to compare yet.",
                    tone: neut
                )
            }
            let firstD = NSDecimalNumber(decimal: first).doubleValue
            let lastD = NSDecimalNumber(decimal: last).doubleValue
            let delta = firstD > 0 ? (lastD - firstD) / firstD : 0
            if abs(delta) < 0.01 {
                return SignalTile(
                    icon: "equal.circle",
                    title: "Price history",
                    detail: "Charge has been stable at \(formatCurrency(last)) across \(membership.chargeHistory.count) hits.",
                    tone: good
                )
            }
            let pct = Int((delta * 100).rounded())
            let tone: Color = abs(delta) > 0.10 ? alert : warn
            return SignalTile(
                icon: delta > 0 ? "arrow.up.right" : "arrow.down.right",
                title: "Price history",
                detail: "Up \(pct)% from your first charge of \(formatCurrency(first)) — now \(formatCurrency(last)).",
                tone: tone
            )
        }()

        // ALTERNATIVES — pull from catalog.
        let alternativesText: String = {
            guard let domain = membership.logoDomain else {
                return "No curated alternatives — search the App Store for cheaper picks."
            }
            let list = CancellationGuideCatalog.alternatives(for: domain)
            if list.isEmpty {
                return "No curated alternatives — search the App Store for cheaper picks."
            }
            return list.prefix(3).joined(separator: " · ")
        }()
        let alternatives = SignalTile(
            icon: "arrow.triangle.swap",
            title: "Alternatives",
            detail: alternativesText,
            tone: neut
        )

        // AI SUGGESTS — pick the highest-savings tip if any.
        let suggest: SignalTile = {
            if let top = membership.optimizationTips.first {
                return SignalTile(
                    icon: top.kind.icon,
                    title: "AI suggests",
                    detail: top.rationale,
                    tone: warn
                )
            }
            return SignalTile(
                icon: "checkmark.seal",
                title: "AI suggests",
                detail: "No action recommended — this membership looks well-priced for the value.",
                tone: good
            )
        }()

        // CANCELLATION FRICTION — pull from guide.
        let friction: SignalTile = {
            guard let guide = membership.cancellationGuide else {
                return SignalTile(
                    icon: "questionmark.circle",
                    title: "Cancellation friction",
                    detail: "No cancellation guide yet — open the merchant's website to manage the subscription.",
                    tone: neut
                )
            }
            let tone: Color = {
                switch guide.frictionLevel {
                case .easy: return good
                case .moderate: return warn
                case .hard: return alert
                }
            }()
            return SignalTile(
                icon: frictionIcon(for: guide.frictionLevel),
                title: "Cancellation friction",
                detail: "\(guide.frictionLevel.displayLabel) — \(guide.steps.count) steps, ~\(guide.averageTimeMinutes) min.",
                tone: tone
            )
        }()

        // ANNUAL VS MONTHLY — only run the math when the catalog has
        // a real annual figure.
        let annual: SignalTile = {
            if let domain = membership.logoDomain,
               CancellationGuideCatalog.hasAnnualPlan(for: domain),
               let annualPrice = CancellationGuideCatalog.annualPrice(for: domain) {
                let annualMonthly = annualPrice / 12
                let saving = membership.monthlyCost - annualMonthly
                if saving > 0 {
                    return SignalTile(
                        icon: "calendar",
                        title: "Annual vs monthly",
                        detail: "Annual \(formatCurrency(annualPrice))/yr — that's \(formatCurrency(annualMonthly))/mo, saving \(formatCurrency(saving))/mo.",
                        tone: good
                    )
                }
                return SignalTile(
                    icon: "calendar",
                    title: "Annual vs monthly",
                    detail: "Annual plan is \(formatCurrency(annualPrice))/yr — not cheaper than your current monthly bill.",
                    tone: neut
                )
            }
            return SignalTile(
                icon: "calendar",
                title: "Annual vs monthly",
                detail: "\(membership.merchant) doesn't publicly offer an annual tier we can recommend.",
                tone: neut
            )
        }()

        return [usage, price, alternatives, suggest, friction, annual]
    }

    private func frictionIcon(for level: FrictionLevel) -> String {
        switch level {
        case .easy:     return "bolt.fill"
        case .moderate: return "wrench"
        case .hard:     return "lock.fill"
        }
    }

    // MARK: - Charge history

    @ViewBuilder
    private func chargeHistorySection(tokens: TokenSet) -> some View {
        let recent = membership.chargeHistory.suffix(6)
        VStack(alignment: .leading, spacing: 10) {
            Text("CHARGE HISTORY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            sparkline(tokens: tokens)
                .frame(height: 56)
                .padding(.horizontal, 4)
            VStack(spacing: 2) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { _, pt in
                    HStack {
                        Text(formatDate(pt.date))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                        Spacer()
                        Text(formatCurrency(pt.amount))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.foregroundPrimary.color.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sparkline(tokens: TokenSet) -> some View {
        let amounts = membership.chargeHistory.map {
            NSDecimalNumber(decimal: $0.amount).doubleValue
        }
        if amounts.count < 2 {
            HStack {
                Spacer()
                Text("Need at least 2 charges for a sparkline")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
        } else {
            GeometryReader { geo in
                let minV = amounts.min() ?? 0
                let maxV = amounts.max() ?? 1
                let range = max(maxV - minV, 0.01)
                let step = amounts.count > 1 ? geo.size.width / CGFloat(amounts.count - 1) : 0
                Path { p in
                    for (i, v) in amounts.enumerated() {
                        let x = CGFloat(i) * step
                        let yNorm = (v - minV) / range
                        let y = geo.size.height - CGFloat(yNorm) * geo.size.height
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else      { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(
                    MembershipStatusPill.tone(for: membership.status),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Cancellation card

    @ViewBuilder
    private func cancellationCard(tokens: TokenSet) -> some View {
        if let guide = membership.cancellationGuide {
            VStack(alignment: .leading, spacing: 12) {
                Text("CANCELLATION GUIDE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)

                HStack(spacing: 8) {
                    frictionChip(for: guide.frictionLevel)
                    timeChip(minutes: guide.averageTimeMinutes, tokens: tokens)
                    if guide.source == .hardcoded {
                        sourceChip(label: "Curated", tokens: tokens)
                    } else if guide.source == .llm {
                        sourceChip(label: "AI-generated", tokens: tokens)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                                .frame(width: 16, alignment: .trailing)
                            Text(step)
                                .font(.system(size: 12))
                                .foregroundStyle(tokens.foregroundPrimary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let url = guide.cancelUrl {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Open cancel page".uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(0.7)
                        }
                        .foregroundStyle(Color(red: 0.27, green: 0.83, blue: 0.89))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color(red: 0.27, green: 0.83, blue: 0.89).opacity(0.6), lineWidth: 1)
                        )
                    }
                    .accessibilityIdentifier("memberships.detail.openCancelPage")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.foregroundPrimary.color.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tokens.foregroundPrimary.color.opacity(0.06), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("CANCELLATION GUIDE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("We don't ship a hand-curated cancel walkthrough for \(membership.merchant) yet. Open the merchant's account page to manage the subscription.")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.foregroundPrimary.color.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tokens.foregroundPrimary.color.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func frictionChip(for level: FrictionLevel) -> some View {
        let tone: Color = {
            switch level {
            case .easy:     return Color(red: 0.34, green: 0.78, blue: 0.50)
            case .moderate: return Color(red: 1.00, green: 0.69, blue: 0.22)
            case .hard:     return Color(red: 0.94, green: 0.33, blue: 0.56)
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: frictionIcon(for: level))
                .font(.system(size: 9, weight: .semibold))
            Text(level.displayLabel.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tone.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(tone.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func timeChip(minutes: Int, tokens: TokenSet) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .semibold))
            Text("\(minutes) MIN")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundStyle(tokens.foregroundSecondary.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sourceChip(label: String, tokens: TokenSet) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(tokens.foregroundSecondary.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(tokens.foregroundSecondary.color.opacity(0.4), lineWidth: 1)
            )
    }

    // MARK: - Tips list

    @ViewBuilder
    private func tipsList(tokens: TokenSet) -> some View {
        if !membership.optimizationTips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("OPTIMIZATION TIPS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                VStack(spacing: 8) {
                    ForEach(membership.optimizationTips) { tip in
                        tipRow(tip: tip, tokens: tokens)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tipRow(tip: OptimizationTip, tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 1.00, green: 0.69, blue: 0.22))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(tip.kind.displayLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(tip.rationale)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(formatCurrency(tip.estimatedSavingsMonthly))/mo")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.34, green: 0.78, blue: 0.50))
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.foregroundPrimary.color.opacity(0.06), lineWidth: 1)
        )
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
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }
}
