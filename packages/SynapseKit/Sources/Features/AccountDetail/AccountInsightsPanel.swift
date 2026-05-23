import SwiftUI
import Models
import DesignSystem

/// Six-tile AI insights grid for the macOS account-detail surface.
///
/// Sibling to [[AccountDetailRedesigned]] — the integrator embeds an
/// instance below the KPI cluster, the balance trajectory chart, and
/// the recurrings card. Internal-only by design: the surface composes
/// the panel directly; there is no external consumer.
///
/// All math is local, synchronous, and deterministic. The tiles mirror
/// the chrome of `FinanceTransactionsRedesigned.aiSignalTile`: a
/// monospaced-caps eyebrow, an SF Symbol tinted to the tone color, a
/// short body string, a 132pt-uniform card with a tone-tinted 1pt
/// hairline stroke. The grid is 3 columns × 2 rows so every tile lands
/// at the same height regardless of copy length — the operator can
/// scan the grid by tone the same way the categories surface does.
///
/// Empty-data accounts (no scoped transactions, nil balance) paint a
/// graceful "Awaiting data" body and a neutral tone. Sample fixtures
/// surface a corner "SAMPLE" chip so a demo screen never gets
/// confused with a live capture.
@MainActor
struct AccountInsightsPanel: View {

    @Bindable private var viewModel: AccountDetailViewModel
    private let chrome: CopilotTokens.Shell

    init(
        viewModel: AccountDetailViewModel,
        chrome: CopilotTokens.Shell = CopilotTokens.shell
    ) {
        self.viewModel = viewModel
        self.chrome = chrome
    }

    var body: some View {
        let signals = buildSignals()
        let sample = isSampleData
        let cols = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return VStack(alignment: .leading, spacing: 12) {
            header
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(signals) { signal in
                    tile(for: signal, sample: sample)
                }
            }
        }
        .accessibilityIdentifier("accountInsights.\(viewModel.account.id)")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(toneNeut)
            Text("AI INSIGHTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(chrome.foregroundSecondary.color)
            Spacer()
            if isSampleData {
                sampleChip
            }
        }
    }

    private var sampleChip: some View {
        Text("SAMPLE")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(toneWarn)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .stroke(toneWarn.opacity(0.40), lineWidth: 1)
            )
    }

    // MARK: - Tile chrome

    private func tile(for signal: AISignal, sample: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: signal.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(signal.tone)
                Text(signal.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(chrome.foregroundSecondary.color)
                Spacer(minLength: 4)
                if sample {
                    Text("SAMPLE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(signal.tone.opacity(0.85))
                }
            }
            Text(signal.detail)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(chrome.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            if let chip = signal.chip {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 9, weight: .semibold))
                    Text(chip)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundStyle(signal.tone.opacity(0.85))
            }
        }
        .padding(14)
        // 132pt uniform height mirrors the FinanceTransactionsRedesigned
        // pattern — short bodies don't shrink, long ones cap. Lets the
        // operator scan a 3x2 grid by tone color without the layout
        // jittering as copy varies.
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chrome.foregroundSecondary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(signal.tone.opacity(0.30), lineWidth: 1)
        )
        .accessibilityIdentifier("accountInsights.tile.\(signal.idTag)")
    }

    // MARK: - Signal model

    private struct AISignal: Identifiable {
        let id = UUID()
        let idTag: String
        let icon: String
        let title: String
        let detail: String
        let tone: Color
        let chip: String?
    }

    // MARK: - Signal build

    private func buildSignals() -> [AISignal] {
        [
            spendingVelocityTile(),
            balanceTrajectoryTile(),
            feeDetectionTile(),
            topMerchantTile(),
            recurringLoadTile(),
            projectedNextMonthTile()
        ]
    }

    // 1. SPENDING VELOCITY
    private func spendingVelocityTile() -> AISignal {
        let kpis = viewModel.kpis
        let avgDaily = decimalToDouble(kpis.avgDailySpend)
        let monthSpend = decimalToDouble(kpis.monthSpend)
        if avgDaily <= 0, monthSpend <= 0 {
            return AISignal(
                idTag: "velocity",
                icon: "speedometer",
                title: "Spending velocity",
                detail: awaitingDataCopy,
                tone: toneNeut,
                chip: nil
            )
        }
        let dailyInt = Int(avgDaily.rounded())
        let projected = Int((avgDaily * 30).rounded())

        // Typical = the implied month total (avgDaily * 30) is the
        // 30-day baseline. The actual month-to-date pace, scaled out
        // to a full month, is the comparison number. Subtract to get
        // a directional delta the operator can read.
        let elapsed = max(daysElapsedInMonth, 1)
        let mtdPace = monthSpend / Double(elapsed) * 30.0
        let typical = max(avgDaily * 30.0, 1.0)
        let pctDelta = Int(((mtdPace - typical) / typical * 100.0).rounded())
        let tone: Color
        let directional: String
        if pctDelta > 15 {
            tone = toneWarn
            directional = "\(pctDelta)% above typical"
        } else if pctDelta < -15 {
            tone = toneGood
            directional = "\(abs(pctDelta))% below typical"
        } else {
            tone = toneNeut
            directional = "within \(abs(pctDelta))% of typical"
        }
        let detail = "Tracking $\(formatThousandsInt(dailyInt))/day, on pace for $\(formatThousandsInt(projected)) this month — \(directional)."
        return AISignal(
            idTag: "velocity",
            icon: "speedometer",
            title: "Spending velocity",
            detail: detail,
            tone: tone,
            chip: nil
        )
    }

    // 2. BALANCE TRAJECTORY
    private func balanceTrajectoryTile() -> AISignal {
        let series = viewModel.balanceSeries
        guard let first = series.first, let last = series.last, first != last else {
            return AISignal(
                idTag: "trajectory",
                icon: "chart.line.uptrend.xyaxis",
                title: "Balance trajectory",
                detail: awaitingDataCopy,
                tone: toneNeut,
                chip: nil
            )
        }
        let startVal = decimalToDouble(first.balance)
        let endVal = decimalToDouble(last.balance)
        let absDelta = endVal - startVal
        let pct: Double = abs(startVal) > 0.01
            ? (absDelta / abs(startVal)) * 100.0
            : 0
        let absDeltaInt = Int(abs(absDelta).rounded())
        let pctInt = Int(pct.rounded())
        let isLiability = viewModel.account.kind.isLiability
        let upward = absDelta > 0
        // Asset upward = good. Asset downward = warn.
        // Liability upward (balance owed climbing) = warn.
        // Liability downward (paying it down) = good.
        let tone: Color
        if abs(absDelta) < 1 {
            tone = toneNeut
        } else if isLiability {
            tone = upward ? toneWarn : toneGood
        } else {
            tone = upward ? toneGood : toneWarn
        }
        let direction = upward ? "up" : "down"
        let rangeLabel = rangeLabel(for: viewModel.range)
        let signPrefix = upward ? "+" : "-"
        let detail = "\(direction.capitalized) \(signPrefix)$\(formatThousandsInt(absDeltaInt)) (\(signPrefix)\(abs(pctInt))%) over the last \(rangeLabel). \(isLiability ? "Balance owed " + direction + "." : "Account " + direction + ".")"
        return AISignal(
            idTag: "trajectory",
            icon: upward ? "arrow.up.right" : "arrow.down.right",
            title: "Balance trajectory",
            detail: detail,
            tone: tone,
            chip: nil
        )
    }

    // 3. FEE DETECTION
    private func feeDetectionTile() -> AISignal {
        let cal = Calendar(identifier: .gregorian)
        let cutoff = cal.date(byAdding: .day, value: -30, to: viewModel.today) ?? viewModel.today
        let fees = viewModel.allScopedTransactions.filter { tx in
            guard !tx.pending else { return false }
            guard case .knownCategory(let raw) = tx.category else { return false }
            let upper = raw.uppercased()
            // Match Plaid's "BANK_FEES" / "FEES" buckets and any
            // subcategory the server may surface (overdraft, atm,
            // foreign-transaction). Substring keeps the matcher
            // forward-compatible.
            return upper.contains("FEES") || upper.contains("FEE_")
        }
        let recent = fees.filter { $0.date >= cutoff }
        if fees.isEmpty {
            return AISignal(
                idTag: "fees",
                icon: "shield.checkered",
                title: "Fee detection",
                detail: viewModel.allScopedTransactions.isEmpty
                    ? awaitingDataCopy
                    : "No fees detected on this account. Clean ledger over the trailing window.",
                tone: viewModel.allScopedTransactions.isEmpty ? toneNeut : toneGood,
                chip: nil
            )
        }
        let total = recent.reduce(Decimal.zero) { $0 + absDecimal($1.amount ?? 0) }
        let totalInt = Int(decimalToDouble(total).rounded())
        let count = recent.count
        if count == 0 {
            // Fees exist but not in the last 30 days.
            let allTotal = fees.reduce(Decimal.zero) { $0 + absDecimal($1.amount ?? 0) }
            let allInt = Int(decimalToDouble(allTotal).rounded())
            return AISignal(
                idTag: "fees",
                icon: "shield.checkered",
                title: "Fee detection",
                detail: "\(fees.count) historical fees totalling $\(formatThousandsInt(allInt)) on file, none in the last 30 days.",
                tone: toneNeut,
                chip: nil
            )
        }
        let label = count == 1 ? "1 fee" : "\(count) fees"
        return AISignal(
            idTag: "fees",
            icon: "exclamationmark.triangle.fill",
            title: "Fee detection",
            detail: "\(label) this month ($\(formatThousandsInt(totalInt))) — that's the cheapest budget recovery on the account.",
            tone: toneAlert,
            chip: nil
        )
    }

    // 4. TOP MERCHANT
    private func topMerchantTile() -> AISignal {
        let cal = Calendar(identifier: .gregorian)
        let cutoff = cal.date(byAdding: .day, value: -30, to: viewModel.today) ?? viewModel.today
        let debits = viewModel.allScopedTransactions.filter { tx in
            guard let a = tx.amount, !tx.pending, a < 0 else { return false }
            return tx.date >= cutoff
        }
        if debits.isEmpty {
            return AISignal(
                idTag: "topMerchant",
                icon: "storefront",
                title: "Top merchant",
                detail: awaitingDataCopy,
                tone: toneNeut,
                chip: nil
            )
        }
        let grouped = Dictionary(grouping: debits) { tx -> String in
            // Prefer the cleaned merchantName; fall back to the raw
            // description. Trim and truncate so a 60-char description
            // doesn't blow out the tile body.
            let raw = tx.merchantName?.isEmpty == false
                ? (tx.merchantName ?? "")
                : tx.name
            return String(raw.prefix(28)).trimmingCharacters(in: .whitespaces)
        }
        let totals: [(String, Decimal)] = grouped.map { (k, v) in
            let s = v.reduce(Decimal.zero) { $0 + absDecimal($1.amount ?? 0) }
            return (k, s)
        }
        guard let top = totals.max(by: { $0.1 < $1.1 }) else {
            return AISignal(
                idTag: "topMerchant",
                icon: "storefront",
                title: "Top merchant",
                detail: awaitingDataCopy,
                tone: toneNeut,
                chip: nil
            )
        }
        let allSpend = debits.reduce(Decimal.zero) { $0 + absDecimal($1.amount ?? 0) }
        let allD = decimalToDouble(allSpend)
        let topD = decimalToDouble(top.1)
        let share = allD > 0 ? Int((topD / allD * 100.0).rounded()) : 0
        let topInt = Int(topD.rounded())
        let tone: Color = share > 40 ? toneWarn : toneNeut
        let suffix = share > 40
            ? "Heavy concentration — worth a glance."
            : "Diversified across multiple merchants."
        let name = top.0.isEmpty ? "Unknown merchant" : top.0
        let detail = "\(name) — $\(formatThousandsInt(topInt)) (\(share)% of last 30 days). \(suffix)"
        return AISignal(
            idTag: "topMerchant",
            icon: "storefront",
            title: "Top merchant",
            detail: detail,
            tone: tone,
            chip: nil
        )
    }

    // 5. RECURRING LOAD
    private func recurringLoadTile() -> AISignal {
        let recs = viewModel.recurrings
        if recs.isEmpty {
            return AISignal(
                idTag: "recurring",
                icon: "repeat",
                title: "Recurring load",
                detail: viewModel.allScopedTransactions.isEmpty
                    ? awaitingDataCopy
                    : "No recurring charges detected on this account yet. Cadence-based detector needs at least 3 hits.",
                tone: toneNeut,
                chip: nil
            )
        }
        let total = recs.reduce(Decimal.zero) { $0 + $1.medianAmount }
        let totalInt = Int(decimalToDouble(total).rounded())
        let count = recs.count
        let label = count == 1 ? "1 recurring" : "\(count) recurrings"
        let detail = "\(label) = $\(formatThousandsInt(totalInt))/month locked in on this account."
        return AISignal(
            idTag: "recurring",
            icon: "repeat",
            title: "Recurring load",
            detail: detail,
            tone: toneNeut,
            chip: nil
        )
    }

    // 6. PROJECTED NEXT MONTH
    private func projectedNextMonthTile() -> AISignal {
        let kpis = viewModel.kpis
        let monthSpend = decimalToDouble(kpis.monthSpend)
        let avgDaily = decimalToDouble(kpis.avgDailySpend)
        let elapsed = max(daysElapsedInMonth, 1)
        if monthSpend <= 0, avgDaily <= 0 {
            return AISignal(
                idTag: "projection",
                icon: "calendar.badge.clock",
                title: "Projected next month",
                detail: awaitingDataCopy,
                tone: toneNeut,
                chip: nil
            )
        }
        // Project full-month total from month-to-date. The brief
        // wants `monthSpend / daysElapsedInMonth * 30` — that's a
        // linear extrapolation that overshoots on quiet end-of-month
        // tails, but it's the honest reading of the current pace.
        let projected = monthSpend / Double(elapsed) * 30.0
        let typical = max(avgDaily * 30.0, 1.0)
        let pctVsTypical = Int(((projected - typical) / typical * 100.0).rounded())
        let tone: Color = pctVsTypical <= 5 ? toneGood : toneWarn
        let projectedInt = Int(projected.rounded())
        // Confidence rises with the number of days observed in the
        // current month — 7 days = ~25%, 30 days = ~95%. Cap at 95
        // so the chip never lies about being certain.
        let confidence = min(95, Int(((Double(elapsed) / 30.0) * 95.0).rounded()))
        let comparison = pctVsTypical > 0
            ? "+\(pctVsTypical)% vs typical"
            : "\(pctVsTypical)% vs typical"
        let detail = "Linear pace lands near $\(formatThousandsInt(projectedInt)) by month-end — \(comparison)."
        return AISignal(
            idTag: "projection",
            icon: "calendar.badge.clock",
            title: "Projected next month",
            detail: detail,
            tone: tone,
            chip: "\(confidence)% conf"
        )
    }

    // MARK: - Helpers

    private var daysElapsedInMonth: Int {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.day], from: viewModel.today)
        return comps.day ?? 1
    }

    private var isSampleData: Bool {
        let txs = viewModel.allScopedTransactions
        if txs.isEmpty { return true }
        return txs.contains { tx in
            let n = tx.name
            return n.hasPrefix("Sample ") || n.hasPrefix("Demo ")
        }
    }

    private var awaitingDataCopy: String {
        "Awaiting data — this account has no ledger activity to learn from yet."
    }

    private func rangeLabel(for range: AccountDetailBalanceSeries.Range) -> String {
        switch range {
        case .d7:  return "7 days"
        case .d30: return "30 days"
        case .d90: return "90 days"
        case .d1y: return "year"
        case .all: return "history"
        }
    }

    private func decimalToDouble(_ d: Decimal) -> Double {
        NSDecimalNumber(decimal: d).doubleValue
    }

    private func absDecimal(_ d: Decimal) -> Decimal {
        d < 0 ? -d : d
    }

    private func formatThousandsInt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    // MARK: - Tone palette

    // Mirrored from FinanceTransactionsRedesigned so a tile in this
    // panel reads at the same temperature as a tile on the categories
    // surface. If the brand updates, both surfaces refresh together.
    private var toneGood: Color  { Color(red: 0.34, green: 0.78, blue: 0.50) }
    private var toneWarn: Color  { Color(red: 1.00, green: 0.69, blue: 0.22) }
    private var toneNeut: Color  { Color(red: 0.27, green: 0.83, blue: 0.89) }
    private var toneAlert: Color { Color(red: 0.94, green: 0.33, blue: 0.56) }
}
