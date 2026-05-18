import Foundation

/// Enriched view layered on top of a `DetectedSubscription`. Carries
/// the raw detection signal plus the cancellation guide, optimization
/// tips, charge history, and merchant logo domain so the views can
/// render without re-running the detector.
public struct Membership: Sendable, Hashable, Identifiable {
    public let id: String
    public let merchant: String
    public let monthlyCost: Decimal
    public let annualCost: Decimal
    public let currency: String
    public let cadenceDays: Int
    public let firstSeenAt: Date
    public let lastChargedAt: Date
    public let nextExpectedAt: Date
    public let occurrenceCount: Int
    public let status: MembershipStatus
    public let logoDomain: String?
    public let sourceTransactionIds: [String]
    public let cancellationGuide: CancellationGuide?
    public let optimizationTips: [OptimizationTip]
    public let chargeHistory: [ChargeHistoryPoint]
    public let confidence: Double
    public let isSample: Bool

    public init(
        id: String,
        merchant: String,
        monthlyCost: Decimal,
        annualCost: Decimal,
        currency: String = "USD",
        cadenceDays: Int,
        firstSeenAt: Date,
        lastChargedAt: Date,
        nextExpectedAt: Date,
        occurrenceCount: Int,
        status: MembershipStatus,
        logoDomain: String? = nil,
        sourceTransactionIds: [String] = [],
        cancellationGuide: CancellationGuide? = nil,
        optimizationTips: [OptimizationTip] = [],
        chargeHistory: [ChargeHistoryPoint] = [],
        confidence: Double = 0.9,
        isSample: Bool = false
    ) {
        self.id = id
        self.merchant = merchant
        self.monthlyCost = monthlyCost
        self.annualCost = annualCost
        self.currency = currency
        self.cadenceDays = cadenceDays
        self.firstSeenAt = firstSeenAt
        self.lastChargedAt = lastChargedAt
        self.nextExpectedAt = nextExpectedAt
        self.occurrenceCount = occurrenceCount
        self.status = status
        self.logoDomain = logoDomain
        self.sourceTransactionIds = sourceTransactionIds
        self.cancellationGuide = cancellationGuide
        self.optimizationTips = optimizationTips
        self.chargeHistory = chargeHistory
        self.confidence = confidence
        self.isSample = isSample
    }
}

public enum MembershipStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case active
    case trial
    case unused
    case atRisk
    case cancelled

    public var displayLabel: String {
        switch self {
        case .active:    return "Active"
        case .trial:     return "Trial"
        case .unused:    return "Low usage"
        case .atRisk:    return "At risk"
        case .cancelled: return "Cancelled"
        }
    }
}

public struct ChargeHistoryPoint: Sendable, Hashable, Identifiable, Codable {
    public let id: String      // transactionId
    public let date: Date
    public let amount: Decimal

    public init(id: String, date: Date, amount: Decimal) {
        self.id = id
        self.date = date
        self.amount = amount
    }
}

/// AI-generated (or hardcoded) cancellation walkthrough.
public struct CancellationGuide: Sendable, Hashable, Codable {
    public let steps: [String]
    public let averageTimeMinutes: Int
    public let frictionLevel: FrictionLevel
    public let cancelUrl: URL?
    public let source: GuideSource
    public let generatedAt: Date

    public init(
        steps: [String],
        averageTimeMinutes: Int,
        frictionLevel: FrictionLevel,
        cancelUrl: URL? = nil,
        source: GuideSource,
        generatedAt: Date = Date()
    ) {
        self.steps = steps
        self.averageTimeMinutes = averageTimeMinutes
        self.frictionLevel = frictionLevel
        self.cancelUrl = cancelUrl
        self.source = source
        self.generatedAt = generatedAt
    }
}

public enum FrictionLevel: String, Sendable, Hashable, Codable {
    case easy      // 1 click in account
    case moderate  // navigate to settings, confirm
    case hard      // chat / phone / retention offer

    public var displayLabel: String {
        switch self {
        case .easy:     return "Easy"
        case .moderate: return "Moderate"
        case .hard:     return "Hard"
        }
    }
}

public enum GuideSource: String, Sendable, Hashable, Codable {
    case hardcoded, llm, fallback
}

/// One actionable recommendation for a membership.
public struct OptimizationTip: Sendable, Hashable, Identifiable {
    public let merchantId: String
    public let kind: TipKind
    public let rationale: String
    public let estimatedSavingsMonthly: Decimal

    public var id: String { "\(merchantId).\(kind.rawValue)" }

    public init(
        merchantId: String,
        kind: TipKind,
        rationale: String,
        estimatedSavingsMonthly: Decimal
    ) {
        self.merchantId = merchantId
        self.kind = kind
        self.rationale = rationale
        self.estimatedSavingsMonthly = estimatedSavingsMonthly
    }
}

public enum TipKind: String, Sendable, Hashable, Codable {
    case downgrade
    case switchToAnnual
    case cancelDuplicate
    case cancelUnused
    case pauseTrialBeforeRollover

    public var displayLabel: String {
        switch self {
        case .downgrade:                return "Downgrade tier"
        case .switchToAnnual:           return "Switch to annual"
        case .cancelDuplicate:          return "Cancel duplicate"
        case .cancelUnused:             return "Cancel — low usage"
        case .pauseTrialBeforeRollover: return "Pause before rollover"
        }
    }

    public var icon: String {
        switch self {
        case .downgrade:                return "arrow.down.right.circle.fill"
        case .switchToAnnual:           return "calendar.badge.exclamationmark"
        case .cancelDuplicate:          return "rectangle.on.rectangle.slash"
        case .cancelUnused:             return "xmark.circle.fill"
        case .pauseTrialBeforeRollover: return "pause.circle.fill"
        }
    }
}

/// Collection of memberships clustered as duplicates (e.g. Spotify +
/// Apple Music both detected; only one is really needed).
public struct DuplicateCluster: Sendable, Hashable, Identifiable {
    public let id: String         // category key
    public let categoryLabel: String
    public let memberships: [Membership]
    public let estimatedSavingsMonthly: Decimal

    public init(
        id: String,
        categoryLabel: String,
        memberships: [Membership],
        estimatedSavingsMonthly: Decimal
    ) {
        self.id = id
        self.categoryLabel = categoryLabel
        self.memberships = memberships
        self.estimatedSavingsMonthly = estimatedSavingsMonthly
    }
}

/// Top-of-tab AI summary roll-up.
public struct OptimizationSummary: Sendable, Hashable {
    public let totalPotentialSavingsMonthly: Decimal
    public let actionableTipCount: Int
    public let topTips: [OptimizationTip]   // ≤ 3

    public init(
        totalPotentialSavingsMonthly: Decimal,
        actionableTipCount: Int,
        topTips: [OptimizationTip]
    ) {
        self.totalPotentialSavingsMonthly = totalPotentialSavingsMonthly
        self.actionableTipCount = actionableTipCount
        self.topTips = topTips
    }
}
