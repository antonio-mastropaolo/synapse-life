import Foundation
import SwiftUI

/// What kind of goal this is. Drives icon + tint in the UI and is
/// the primary signal the AI-tip-to-goal parser uses to pick a
/// `GoalTarget` shape.
public enum GoalKind: String, Sendable, Hashable, Codable, CaseIterable {
    case reduceCategorySpend
    case capMerchantSpend
    case cancelSubscription
    case increaseSavings
    case buildEmergencyFund
    case custom

    public var icon: String {
        switch self {
        case .reduceCategorySpend: return "arrow.down.circle.fill"
        case .capMerchantSpend:    return "lock.circle.fill"
        case .cancelSubscription:  return "xmark.circle.fill"
        case .increaseSavings:     return "arrow.up.right.circle.fill"
        case .buildEmergencyFund:  return "shield.lefthalf.filled"
        case .custom:              return "target"
        }
    }

    public var tint: Color {
        switch self {
        case .reduceCategorySpend: return Color(red: 1.00, green: 0.69, blue: 0.22)
        case .capMerchantSpend:    return Color(red: 0.94, green: 0.33, blue: 0.56)
        case .cancelSubscription:  return Color(red: 0.93, green: 0.46, blue: 0.34)
        case .increaseSavings:     return Color(red: 0.34, green: 0.78, blue: 0.50)
        case .buildEmergencyFund:  return Color(red: 0.27, green: 0.83, blue: 0.89)
        case .custom:              return Color(red: 0.58, green: 0.66, blue: 0.74)
        }
    }

    public var displayLabel: String {
        switch self {
        case .reduceCategorySpend: return "Reduce category spend"
        case .capMerchantSpend:    return "Cap merchant spend"
        case .cancelSubscription:  return "Cancel subscription"
        case .increaseSavings:     return "Increase savings"
        case .buildEmergencyFund:  return "Build emergency fund"
        case .custom:              return "Custom"
        }
    }
}
