import SwiftUI

/// Tiny line chart of actual vs target across the last N weekly
/// results. Pure presentation, deterministic geometry — same flavor
/// as `forecastSparkline` in DashboardAIInsightsPanel.
@MainActor
struct GoalProgressSparkline: View {
    let results: [GoalWeeklyResult]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let points = results.suffix(10)
            let values = points.map { ($0.actualValue as NSDecimalNumber).doubleValue }
            let targets = points.map { ($0.targetValue as NSDecimalNumber).doubleValue }
            let allVals = values + targets
            let minV = allVals.min() ?? 0
            let maxV = allVals.max() ?? 1
            let range = max(maxV - minV, 1)
            let step = points.count > 1
                ? geo.size.width / CGFloat(points.count - 1)
                : 0

            ZStack(alignment: .leading) {
                // Target line — flat dashed reference.
                if let t = targets.first {
                    let y = geo.size.height - CGFloat((t - minV) / range) * geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(accent.opacity(0.30),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                // Actual line.
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = geo.size.height - CGFloat((v - minV) / range) * geo.size.height
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                // Outcome dots.
                ForEach(Array(points.enumerated()), id: \.element.id) { i, r in
                    let v = (r.actualValue as NSDecimalNumber).doubleValue
                    let x = CGFloat(i) * step
                    let y = geo.size.height - CGFloat((v - minV) / range) * geo.size.height
                    Circle()
                        .fill(r.outcome == .hit ? Color(red: 0.34, green: 0.78, blue: 0.50) : Color(red: 0.94, green: 0.33, blue: 0.56))
                        .frame(width: 6, height: 6)
                        .offset(x: x - 3, y: y - 3)
                }
            }
        }
    }
}
