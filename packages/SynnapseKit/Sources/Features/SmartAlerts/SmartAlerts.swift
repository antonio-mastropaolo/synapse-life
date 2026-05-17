import Foundation
import Models

/// One alert rule the user has installed. Three kinds today; new kinds
/// add a case here + a matching branch in `SmartAlertsEngine.evaluate`.
public struct AlertRule: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let kind: Kind
    public let enabled: Bool
    public let createdAt: Date
    /// Whether the engine surfaced this rule itself (AI-suggested) or
    /// the user installed it manually. Drives the "AI suggested" label
    /// on the row.
    public let isAISuggested: Bool

    public init(
        id: String,
        kind: Kind,
        enabled: Bool = true,
        createdAt: Date = Date(),
        isAISuggested: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.enabled = enabled
        self.createdAt = createdAt
        self.isAISuggested = isAISuggested
    }

    public enum Kind: Sendable, Hashable, Codable {
        /// Fires when any account of the given kind drops below the
        /// threshold balance.
        case balanceLow(accountKind: AccountKind, threshold: Decimal)
        /// Fires whenever the recurring detector finds a brand-new
        /// subscription not previously seen in the snapshot.
        case newRecurring
        /// Fires when a single category's daily total exceeds
        /// `dailyThreshold`. Optionally scoped to a category label;
        /// nil = any category.
        case unusualSpend(categoryLabel: String?, dailyThreshold: Decimal)

        public var label: String {
            switch self {
            case .balanceLow(let kind, let threshold):
                return "Alert when \(kind.rawValue) < \(formatCurrency(threshold))"
            case .newRecurring:
                return "Alert when a new recurring is detected"
            case .unusualSpend(let cat, let t):
                let scope = cat ?? "any category"
                return "Alert when \(scope) spend > \(formatCurrency(t)) in a single day"
            }
        }
    }
}

/// One alert that fired in the current evaluation. The `ruleId` ties
/// it back to its rule; `subjectId` is the transaction or account that
/// triggered the fire (used for citation jump).
public struct FiredAlert: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let ruleId: String
    public let firedAt: Date
    public let subjectId: String?
    public let headline: String
    public let body: String
    public let severity: Severity

    public init(
        id: String,
        ruleId: String,
        firedAt: Date,
        subjectId: String?,
        headline: String,
        body: String,
        severity: Severity = .info
    ) {
        self.id = id
        self.ruleId = ruleId
        self.firedAt = firedAt
        self.subjectId = subjectId
        self.headline = headline
        self.body = body
        self.severity = severity
    }

    public enum Severity: String, Sendable, Hashable, Codable {
        case info
        case warning
        case alert
    }
}

/// The snapshot the rules engine sees on each evaluation pass.
/// `priorMerchants` is the set of merchant names already known so the
/// `newRecurring` rule can detect what's truly new.
public struct AlertsSnapshot: Sendable {
    public let accounts: [FinanceAccount]
    public let transactions: [Transaction]
    public let priorMerchants: Set<String>
    public let now: Date

    public init(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        priorMerchants: Set<String> = [],
        now: Date = Date()
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.priorMerchants = priorMerchants
        self.now = now
    }
}
