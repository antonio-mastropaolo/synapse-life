import SwiftUI
import Charts
import DesignSystem

/// Tiny 7-point sparkline for the NET THIS WEEK hero card.
///
/// Reads `Decimal` buckets and renders a Swift Charts `LineMark` with a
/// faded `AreaMark` underneath. The chart is width-flexible and height
/// 28pt so it sits inside the hero card without fighting the headline
/// figure. No axes, no legend — this is glanceable chrome.
///
/// The bridge through `NSDecimalNumber.doubleValue` is the canonical
/// move (see [[feedback_decimal_from_double]]) — the data is for a
/// visual chart, not a money-math operation, so the lossy hop is
/// deliberate. The reducer keeps the canonical `Decimal` series.
@MainActor
struct DashboardSparkline: View {

    /// 7 day-buckets, oldest first. Mirror of
    /// `DashboardWidgetReducer.NetThisWeek.sparkline`.
    let values: [Decimal]

    let tint: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                LineMark(
                    x: .value("day", idx),
                    y: .value("net", asDouble(value))
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("day", idx),
                    y: .value("net", asDouble(value))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.32), tint.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 28)
        .accessibilityHidden(true) // The card's parent already
                                   // narrates "Net this week, $X".
    }

    private func asDouble(_ d: Decimal) -> Double {
        NSDecimalNumber(decimal: d).doubleValue
    }
}
