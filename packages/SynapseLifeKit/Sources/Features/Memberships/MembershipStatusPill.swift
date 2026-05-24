import SwiftUI
import DesignSystem

/// Compact status chip rendered next to a membership's merchant name.
///
/// One color per status — see the `tone(for:)` helper for the
/// mapping. The pill is intentionally small (10pt monospaced caps);
/// it sits on the row + the detail hero alongside the merchant
/// header without competing visually with the price.
@MainActor
struct MembershipStatusPill: View {
    let status: MembershipStatus

    var body: some View {
        let tone = Self.tone(for: status)
        Text(status.displayLabel.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tone.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(tone.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel("Status: \(status.displayLabel)")
    }

    /// Tone palette. Kept inline so the pill can be used outside the
    /// `theme` env (e.g. from snapshot tests).
    static func tone(for status: MembershipStatus) -> Color {
        switch status {
        case .active:    return Color(red: 0.34, green: 0.78, blue: 0.50)  // green
        case .trial:     return Color(red: 0.27, green: 0.83, blue: 0.89)  // cyan
        case .unused:    return Color(red: 1.00, green: 0.69, blue: 0.22)  // amber
        case .atRisk:    return Color(red: 0.94, green: 0.33, blue: 0.56)  // pink
        case .cancelled: return Color.gray
        }
    }
}
