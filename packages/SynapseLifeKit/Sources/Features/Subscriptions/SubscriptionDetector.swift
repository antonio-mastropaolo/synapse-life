import Foundation
import Models

/// One detected subscription. A subscription is a *strict* subset of
/// the recurring set: same merchant, fixed cadence in
/// {30, 90, 365} days, and amount stable within ±5% across
/// occurrences. The `monthlyEquivalent` carries the yearly figure
/// divided by 12 (or the quarterly figure divided by 3) so the UI can
/// render a single "$/mo" column regardless of billing frequency.
public struct DetectedSubscription: Sendable, Hashable, Identifiable {

    public var id: String { "subscription.\(merchant.lowercased().replacingOccurrences(of: " ", with: "-"))" }

    public let merchant: String
    public let category: CategoryID
    public let amount: Decimal            // raw charge amount per cadence
    public let cadenceDays: Int            // 30 / 90 / 365
    public let monthlyEquivalent: Decimal  // amount normalized to a monthly figure
    public let lastCharged: Date
    public let nextExpected: Date
    public let occurrenceCount: Int
    public let confidence: Double
    public let transactionIds: [String]

    public init(
        merchant: String,
        category: CategoryID,
        amount: Decimal,
        cadenceDays: Int,
        monthlyEquivalent: Decimal,
        lastCharged: Date,
        nextExpected: Date,
        occurrenceCount: Int,
        confidence: Double,
        transactionIds: [String]
    ) {
        self.merchant = merchant
        self.category = category
        self.amount = amount
        self.cadenceDays = cadenceDays
        self.monthlyEquivalent = monthlyEquivalent
        self.lastCharged = lastCharged
        self.nextExpected = nextExpected
        self.occurrenceCount = occurrenceCount
        self.confidence = confidence
        self.transactionIds = transactionIds
    }

    /// Cadence label used by the UI.
    public var cadenceLabel: String {
        switch cadenceDays {
        case 30: return "Monthly"
        case 90: return "Quarterly"
        case 365: return "Yearly"
        default: return "Every \(cadenceDays) days"
        }
    }
}

/// Pure-logic specialization on top of [[RecurringDetector]] that
/// filters down to charges that look like SaaS / streaming
/// subscriptions: same amount, cadence in {30, 90, 365}, category =
/// `subscriptions`. The "amount stable within ±5%" check rules out
/// things like AFFIRM payments (which look monthly but vary every
/// month) and gym memberships with surprise annual fees.
public enum SubscriptionDetector {

    public static let amountTolerance: Double = 0.05
    public static let allowedCadences: Set<Int> = [30, 90, 365]

    public static func detectSubscriptions(
        transactions: [Transaction],
        today: Date = Date()
    ) -> [DetectedSubscription] {

        // Start from the same canonical recurring detection so the
        // two views (Recurrings and Subscriptions) never disagree on
        // who is recurring.
        let recurrings = RecurringDetector.detectRecurrings(
            transactions: transactions,
            today: today
        )

        var out: [DetectedSubscription] = []
        for r in recurrings {
            guard allowedCadences.contains(r.cadenceDays) else { continue }

            // Re-look up the transactions that justified this
            // detection so we can run a stricter amount-stability
            // check than the upstream detector does.
            let rows = transactions
                .filter { r.transactionIds.contains($0.id) }
                .compactMap { tx -> (Transaction, Decimal)? in
                    guard let a = tx.amount else { return nil }
                    let absAmt: Decimal = a < 0 ? -a : a
                    return (tx, absAmt)
                }
            guard !rows.isEmpty else { continue }

            // Amount stability: every charge within ±5% of the median.
            let med = r.medianAmount
            let medDouble = NSDecimalNumber(decimal: med).doubleValue
            guard medDouble > 0 else { continue }
            let stable = rows.allSatisfy { _, amount in
                let delta = abs(NSDecimalNumber(decimal: amount).doubleValue - medDouble) / medDouble
                return delta <= amountTolerance
            }
            guard stable else { continue }

            // Category must read as a subscription. We accept the
            // detector's category-of-most-occurrences mapping but
            // also let merchant-token fallback fire — some banks
            // mis-categorize Netflix as "Entertainment".
            let isSubscriptionCategory = r.category == .subscriptions
                || merchantLooksLikeSubscription(r.merchant)
            guard isSubscriptionCategory else { continue }

            let monthly = monthlyEquivalent(amount: med, cadenceDays: r.cadenceDays)

            out.append(DetectedSubscription(
                merchant: r.merchant,
                category: .subscriptions,
                amount: med,
                cadenceDays: r.cadenceDays,
                monthlyEquivalent: monthly,
                lastCharged: r.lastSeen,
                nextExpected: r.predictedNext,
                occurrenceCount: r.occurrenceCount,
                confidence: r.confidence,
                transactionIds: r.transactionIds
            ))
        }
        // Sort by monthlyEquivalent desc so the "what's costing me
        // the most" reading is at the top.
        return out.sorted { lhs, rhs in
            if lhs.monthlyEquivalent == rhs.monthlyEquivalent {
                return lhs.merchant < rhs.merchant
            }
            return lhs.monthlyEquivalent > rhs.monthlyEquivalent
        }
    }

    /// Sum of monthly-equivalent costs.
    public static func monthlyTotal(_ subs: [DetectedSubscription]) -> Decimal {
        subs.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
    }

    /// Sum of yearly-equivalent costs (monthly * 12).
    public static func yearlyTotal(_ subs: [DetectedSubscription]) -> Decimal {
        monthlyTotal(subs) * 12
    }

    // MARK: - Helpers

    static func monthlyEquivalent(amount: Decimal, cadenceDays: Int) -> Decimal {
        switch cadenceDays {
        case 30:  return amount
        case 90:  return amount / 3
        case 365: return amount / 12
        default:  return amount
        }
    }

    /// Token-set fallback for merchants whose server category lies
    /// about being a subscription (banks often park streaming under
    /// "Entertainment"). The list is intentionally short — adding
    /// merchants here should be deliberate.
    static let subscriptionMerchantTokens: [String] = [
        "NETFLIX", "SPOTIFY", "HULU", "DISNEY", "HBO", "APPLE",
        "ICLOUD", "ADOBE", "DROPBOX", "GITHUB", "OPENAI",
        "ANTHROPIC", "NYTIMES", "WSJ", "SIRIUS", "CHATGPT"
    ]

    static func merchantLooksLikeSubscription(_ merchant: String) -> Bool {
        let upper = merchant.uppercased()
        return subscriptionMerchantTokens.contains { upper.contains($0) }
    }
}
