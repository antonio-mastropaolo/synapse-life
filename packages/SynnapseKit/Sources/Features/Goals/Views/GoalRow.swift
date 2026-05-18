import SwiftUI
import DesignSystem

/// Single row in the Goals list. Layout: progress ring on the left,
/// title + target + latest delta in the middle, status chip on the
/// right. Tap routes to `GoalDetailView`.
@MainActor
struct GoalRow: View {
    let goal: Goal
    let tokens: TokenSet
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 16) {
                progressRing
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(goal.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                            .lineLimit(1)
                        if goal.isSample {
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
                    }
                    Text(subline)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .lineLimit(1)
                }
                Spacer()
                statusChip
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progressRing: some View {
        let progress = currentProgress
        return ZStack {
            Circle()
                .stroke(goal.kind.tint.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1.0)))
                .stroke(goal.kind.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: goal.kind.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(goal.kind.tint)
        }
        .frame(width: 38, height: 38)
    }

    private var subline: String {
        let latest = goal.weeklyResults.last
        switch goal.target {
        case .spendUnder(let cap):
            let actualString = latest.map { ($0.actualValue as NSDecimalNumber).doubleValue }.map { String(format: "$%.0f", $0) } ?? "—"
            return "\(actualString) of $\((cap as NSDecimalNumber).doubleValue.formatted(.number.precision(.fractionLength(0)))) this week"
        case .saveAtLeast(let target):
            let actualString = latest.map { ($0.actualValue as NSDecimalNumber).doubleValue }.map { String(format: "$%.0f", $0) } ?? "$0"
            return "\(actualString) of $\((target as NSDecimalNumber).doubleValue.formatted(.number.precision(.fractionLength(0)))) saved"
        case .merchantCancelled(let key):
            return "Stay off \(key)"
        case .countAtMost(let cap):
            let actualString = latest.map { ($0.actualValue as NSDecimalNumber).intValue }.map { "\($0)" } ?? "—"
            return "\(actualString) of \(cap) services"
        }
    }

    private var statusChip: some View {
        let (label, color): (String, Color) = {
            switch goal.status {
            case .active:    return ("ACTIVE",    Color(red: 0.27, green: 0.83, blue: 0.89))
            case .completed: return ("COMPLETED", Color(red: 0.34, green: 0.78, blue: 0.50))
            case .missed:    return ("MISSED",    Color(red: 0.94, green: 0.33, blue: 0.56))
            case .archived:  return ("ARCHIVED",  tokens.foregroundSecondary.color)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }

    private var currentProgress: Double {
        if let last = goal.weeklyResults.last {
            return goal.target.progress(actual: last.actualValue)
        }
        return 0.02
    }
}
