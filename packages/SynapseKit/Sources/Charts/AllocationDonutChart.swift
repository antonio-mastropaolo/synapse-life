import SwiftUI
import Charts

/// Renderable slice. Decoupled from `AllocationSlice` so the same component
/// can render investment `InvestmentAllocationSlice` rows too.
public struct DonutSlice: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let value: Decimal
    public let percentage: Decimal
    public let color: Color

    public init(id: String, label: String, value: Decimal, percentage: Decimal, color: Color) {
        self.id = id
        self.label = label
        self.value = value
        self.percentage = percentage
        self.color = color
    }
}

/// Swift Charts donut: SectorMark with `innerRadius: .ratio(0.62)` to
/// match the instrument-gauge aesthetic. Legend lives outside the chart so
/// the donut keeps its dimensions independent of label length.
public struct AllocationDonutChart: View {
    public let slices: [DonutSlice]

    public init(slices: [DonutSlice]) {
        self.slices = slices
    }

    public var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Share", (abs(slice.value) as NSDecimalNumber).doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.0
            )
            .cornerRadius(2)
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
    }
}
