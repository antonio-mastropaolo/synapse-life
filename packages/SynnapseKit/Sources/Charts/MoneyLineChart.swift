import SwiftUI
import Charts

/// One point on a money time series.
public struct MoneyTimePoint: Sendable, Hashable, Identifiable {
    public let id: Date
    public let date: Date
    public let amount: Decimal

    public init(date: Date, amount: Decimal) {
        self.id = date
        self.date = date
        self.amount = amount
    }
}

/// Swift Charts line chart over a `[MoneyTimePoint]`. Decimal values are
/// bridged through NSDecimalNumber.doubleValue at the rendering edge — we
/// never hold a Double for storage or math. Axis formatting uses the
/// system currency formatter so locale-aware separators come for free.
public struct MoneyLineChart: View {
    public let points: [MoneyTimePoint]
    public let currency: String
    public let accent: Color

    public init(points: [MoneyTimePoint], currency: String = "USD", accent: Color = .accentColor) {
        self.points = points
        self.currency = currency
        self.accent = accent
    }

    public var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Amount", (point.amount as NSDecimalNumber).doubleValue)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(accent)
            AreaMark(
                x: .value("Date", point.date),
                y: .value("Amount", (point.amount as NSDecimalNumber).doubleValue)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [accent.opacity(0.35), accent.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        let formatted = Decimal(raw).formatted(.currency(code: currency).precision(.fractionLength(0)))
                        Text(formatted).font(.system(size: 9, design: .monospaced))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel().font(.system(size: 9, design: .monospaced))
            }
        }
    }
}
