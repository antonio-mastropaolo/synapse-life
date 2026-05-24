import SwiftUI
import Charts
import DesignSystem

/// Light-weight event descriptor consumed by [[BalanceProjectionChart]].
///
/// The chart can't import `Features` (the layer that owns
/// `ScheduledFlow`) without creating a cycle — Charts is upstream of
/// Features. So callers project their flows into this narrow shape at
/// the boundary. The projector itself is unaware of the chart; the
/// view model does the mapping.
public struct BalanceProjectionEvent: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case credit, debit }
    public var id: String { "evt.\(kind == .credit ? "c" : "d").\(merchant.lowercased()).\(Int(date.timeIntervalSince1970))" }
    public let merchant: String
    public let amount: Decimal
    public let date: Date
    public let kind: Kind

    public init(merchant: String, amount: Decimal, date: Date, kind: Kind) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.kind = kind
    }
}

/// Forecast v2 chart — solid line for the trailing-14-day history,
/// dashed line for the projection, gradient fill below the projection
/// (gain-tinted above the zero baseline, loss-tinted below), today
/// marker rule, zero-crossing pin, and small triangle annotations per
/// scheduled credit / debit event.
///
/// Mirrors [[MoneyLineChart]]'s `MoneyTimePoint` data shape and the
/// Decimal→Double bridging at the rendering edge — Decimal is the
/// authoritative type, never Double.
@MainActor
public struct BalanceProjectionChart: View {

    public let historical: [MoneyTimePoint]
    public let projection: [MoneyTimePoint]
    public let events: [BalanceProjectionEvent]
    public let zeroCrossing: Date?
    public let today: Date

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(
        historical: [MoneyTimePoint],
        projection: [MoneyTimePoint],
        events: [BalanceProjectionEvent],
        zeroCrossing: Date?,
        today: Date
    ) {
        self.historical = historical
        self.projection = projection
        self.events = events
        self.zeroCrossing = zeroCrossing
        self.today = today
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        let accent = tokens.accent.color
        let gain = tokens.gainAccent.color
        let loss = tokens.lossAccent.color

        Chart {
            // Historical solid line — anchored at the projection's
            // starting balance walked backwards 14 deterministic days.
            ForEach(historical) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", (point.amount as NSDecimalNumber).doubleValue),
                    series: .value("Series", "historical")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
            }

            // Projection dashed line — picks up where historical ended.
            ForEach(projection) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", (point.amount as NSDecimalNumber).doubleValue),
                    series: .value("Series", "projection")
                )
                .interpolationMethod(.monotone)
                .lineStyle(.init(dash: [4, 3]))
                .foregroundStyle(accent)
            }

            // Gradient fill under the projection. We pick the tint
            // from the trajectory of the projection itself: rising
            // ends gain-tinted, falling ends loss-tinted. The lookup
            // happens once at render — not per-point — so the area
            // stays a single coherent wash.
            ForEach(projection) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Amount", (point.amount as NSDecimalNumber).doubleValue),
                    series: .value("Series", "projection-area")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            projectionTrend >= 0 ? gain.opacity(0.18) : loss.opacity(0.22),
                            (projectionTrend >= 0 ? gain : loss).opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Today's vertical rule.
            RuleMark(x: .value("Today", today))
                .lineStyle(.init(lineWidth: 1, dash: [2, 2]))
                .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.6))
                .annotation(position: .top, alignment: .leading) {
                    Text("TODAY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }

            // Zero crossing pin — only painted when the projection
            // actually dips to/under zero. The point sits on the
            // zero baseline because that's the semantically correct
            // y-value, even though the daily series may briefly be
            // negative at that crossing.
            if let zero = zeroCrossing {
                PointMark(
                    x: .value("Zero", zero),
                    y: .value("Amount", 0)
                )
                .foregroundStyle(loss)
                .symbolSize(80)
                .annotation(position: .top, alignment: .center) {
                    Text("Zero crossing")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(loss)
                }
            }

            // Event annotations — small upward triangles for credits,
            // downward for debits. Triangle size scales with amount,
            // clamped to 6..14pt so a $10 charge doesn't disappear
            // and rent doesn't dominate the chart.
            ForEach(events) { event in
                let yValue = yForEvent(event)
                PointMark(
                    x: .value("Date", event.date),
                    y: .value("Marker", yValue)
                )
                .symbol(.circle)
                .symbolSize(0) // Hide the underlying point; the
                // annotation carries the visible shape.
                .annotation(position: .overlay, alignment: .center) {
                    Triangle(pointingUp: event.kind == .credit)
                        .fill(event.kind == .credit ? gain : loss)
                        .frame(
                            width: triangleSize(for: event.amount),
                            height: triangleSize(for: event.amount)
                        )
                        .accessibilityLabel(
                            "\(event.kind == .credit ? "Credit" : "Debit") \(event.merchant)"
                        )
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        let formatted = Decimal(raw).formatted(
                            .currency(code: "USD").precision(.fractionLength(0))
                        )
                        Text(formatted)
                            .font(.system(size: 9, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartXAxis {
            // ≤ 30 days: weekday short labels; > 30: monthly. The
            // bound below is the union of historical + projection,
            // so a 30D forecast paints ~44 axis days — switch to
            // weekly stride when we're past 30 days of projection.
            if projection.count <= 31 {
                AxisMarks(values: .stride(by: .day, count: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 9, design: .monospaced))
                }
            } else {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.system(size: 9, design: .monospaced))
                }
            }
        }
        .accessibilityIdentifier("forecast.balance-projection-chart")
        .accessibilityLabel("Projected checking balance")
    }

    // MARK: - Derived helpers

    /// Sign of the projection's overall trajectory — positive when the
    /// end-of-horizon balance sits above the start, negative when it
    /// sits below, zero (treated as positive) when flat.
    private var projectionTrend: Int {
        guard let first = projection.first?.amount,
              let last = projection.last?.amount else { return 0 }
        if last > first { return 1 }
        if last < first { return -1 }
        return 0
    }

    /// Marker y-value sits on the projection line at the event date
    /// when we can find a matching point, otherwise on the zero
    /// baseline. The marker is a visual anchor, not a quantitative
    /// claim, so the lookup is best-effort.
    private func yForEvent(_ event: BalanceProjectionEvent) -> Double {
        let target = Calendar(identifier: .gregorian).startOfDay(for: event.date)
        if let match = (historical + projection).first(where: {
            Calendar(identifier: .gregorian).startOfDay(for: $0.date) == target
        }) {
            return (match.amount as NSDecimalNumber).doubleValue
        }
        return 0
    }

    private func triangleSize(for amount: Decimal) -> CGFloat {
        // Linear ramp on the log of the amount so a $10 and a $1,000
        // charge are visually distinguishable without one swamping
        // the chart. Clamped to [6, 14].
        let raw = max(1.0, (amount as NSDecimalNumber).doubleValue)
        let logged = log10(raw) // $1 → 0, $10 → 1, $100 → 2, $1000 → 3
        let mapped = 6.0 + (logged * 2.5) // log $1000 ≈ 13.5
        return CGFloat(min(14.0, max(6.0, mapped)))
    }
}

/// Tiny triangle shape used for the credit/debit ticks. SwiftUI ships
/// no built-in triangle and the chart's own symbol set leans circular,
/// so we hand-roll one to keep the visual language tight.
private struct Triangle: Shape {
    let pointingUp: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
