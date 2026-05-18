import Foundation
import Models

/// Pure-function detector that layers a Memberships view on top of the
/// canonical `SubscriptionDetector`.
///
/// The pipeline is intentionally thin: we don't re-do recurring
/// detection (that's `SubscriptionDetector`'s job and the two views
/// must never disagree on who is recurring). Instead we take the
/// detector's output and add:
///
///   * **Utility exclusion** — rent, mortgage, electric, water, ISP,
///     and cable charges look like clean monthly recurrings but they
///     aren't memberships you can cancel via the app; surfacing them
///     here is misleading. The list is short and deliberate; adding to
///     it should require a code change.
///   * **Status classification** — `active` / `trial` / `unused` /
///     `atRisk` / `cancelled`. Rules are documented inline on
///     `classifyStatus(...)` so a future reader can follow the
///     reasoning without re-reading the manifest.
///   * **Logo domain** — via `MerchantLogoResolver.domain(for:)` so
///     the row + detail surfaces can render the brand glyph.
///   * **Charge history** — `[ChargeHistoryPoint]` built by walking
///     the source transactions, sorted ascending by date so the
///     sparkline + "previous 6 charges" list don't have to re-sort.
///   * **Cancellation guide** — looked up from
///     `CancellationGuideCatalog`. The detector only attaches the
///     guide; LLM enrichment is delegated to `MembershipsStore`'s
///     async `enrichGuidesInBackground()` slot (no-op in v1).
public enum MembershipDetector {

    /// Merchants that look recurring but are utilities, rent, or
    /// telecom service-not-membership and should never be shown as a
    /// cancellable membership. Match is uppercased-substring against
    /// `Transaction.name` / `Transaction.merchantName`.
    public static let utilityExclusions: [String] = [
        "RENT", "PG&E", "PGE",
        "CON ED", "CONED",
        "COMCAST", "XFINITY",
        "VERIZON FIOS",
        "AT&T U-VERSE", "U-VERSE",
        "WATER DEPT", "WATER DEPARTMENT", "WATER UTILITY",
        "MORTGAGE", "ELECTRIC COMPANY", "ELECTRIC CO",
        "NATIONAL GRID", "EVERSOURCE"
    ]

    /// Run the detector. Pure function — `today` is the only
    /// non-input source of nondeterminism and is passed in so tests
    /// can pin the clock.
    public static func detect(
        transactions: [Transaction],
        today: Date = Date()
    ) -> [Membership] {
        // Delegate to the canonical subscription detector for the
        // "is this recurring and stable" decision.
        let detected = SubscriptionDetector.detectSubscriptions(
            transactions: transactions,
            today: today
        )

        var out: [Membership] = []
        for sub in detected {
            // Utility exclusion. We check both the detected merchant
            // and the raw transactions because banks sometimes
            // collapse "CONED *NYC" into "CONED" upstream.
            if matchesUtility(merchant: sub.merchant, transactionIds: sub.transactionIds, in: transactions) {
                continue
            }

            // Charge history — sorted ascending so the sparkline
            // renders left-to-right and the price-history tile can
            // compute deltas off `last - secondLast` cleanly.
            let chargeHistory = chargeHistory(for: sub.transactionIds, in: transactions)
            let firstSeen = chargeHistory.first?.date ?? sub.lastCharged

            let domain = MerchantLogoResolver.domain(for: sub.merchant)
            let guide = domain.flatMap { CancellationGuideCatalog.guide(for: $0) }

            let status = classifyStatus(
                today: today,
                lastCharged: sub.lastCharged,
                cadenceDays: sub.cadenceDays,
                occurrenceCount: sub.occurrenceCount,
                monthlyEquivalent: sub.monthlyEquivalent,
                confidence: sub.confidence,
                chargeHistory: chargeHistory
            )

            let monthly = sub.monthlyEquivalent
            let annual  = monthly * 12

            out.append(Membership(
                id: sub.id,
                merchant: sub.merchant,
                monthlyCost: monthly,
                annualCost: annual,
                currency: "USD",
                cadenceDays: sub.cadenceDays,
                firstSeenAt: firstSeen,
                lastChargedAt: sub.lastCharged,
                nextExpectedAt: sub.nextExpected,
                occurrenceCount: sub.occurrenceCount,
                status: status,
                logoDomain: domain,
                sourceTransactionIds: sub.transactionIds,
                cancellationGuide: guide,
                optimizationTips: [],         // filled in by MembershipOptimizer
                chargeHistory: chargeHistory,
                confidence: sub.confidence,
                isSample: false
            ))
        }

        return out.sorted { lhs, rhs in
            if lhs.monthlyCost == rhs.monthlyCost {
                return lhs.merchant < rhs.merchant
            }
            return lhs.monthlyCost > rhs.monthlyCost
        }
    }

    // MARK: - Status

    /// Per the manifest:
    ///   * `cancelled`: today − lastCharged > 2 × cadenceDays
    ///   * `trial`:     occurrenceCount == 1 && monthlyEquivalent ≤ 5
    ///   * `atRisk`:    any pair of consecutive charges differs by
    ///                  > 10% OR monthlyEquivalent > 40
    ///   * `unused`:    monthlyEquivalent < 20 && confidence > 0.85
    ///   * `active`:    otherwise
    ///
    /// Ordered: `cancelled` wins over `atRisk` wins over `trial` wins
    /// over `unused`. That priority ranks the "this charge surprises
    /// you" cases above the soft heuristics so a $20 atRisk charge
    /// doesn't get rendered as just "low usage".
    static func classifyStatus(
        today: Date,
        lastCharged: Date,
        cadenceDays: Int,
        occurrenceCount: Int,
        monthlyEquivalent: Decimal,
        confidence: Double,
        chargeHistory: [ChargeHistoryPoint]
    ) -> MembershipStatus {
        // Cancelled — well past two cadences and the bank hasn't
        // confirmed another charge.
        let twoCadences = TimeInterval(2 * cadenceDays * 86_400)
        if today.timeIntervalSince(lastCharged) > twoCadences {
            return .cancelled
        }

        // atRisk via price drift.
        let priceJump = hasPriceJump(history: chargeHistory, tolerance: 0.10)
        let monthlyDouble = NSDecimalNumber(decimal: monthlyEquivalent).doubleValue
        if priceJump || monthlyDouble > 40 {
            return .atRisk
        }

        // Trial — exactly one charge of a few bucks. We exclude
        // cancelled / atRisk above so a $1.99 charge followed by
        // silence reads as cancelled, not trial.
        if occurrenceCount == 1 && monthlyDouble <= 5 {
            return .trial
        }

        // Unused — soft heuristic. Small recurring charge we've seen
        // multiple times with high confidence — likely a "set and
        // forget" service the user has stopped touching.
        if monthlyDouble < 20 && confidence > 0.85 && occurrenceCount >= 2 {
            return .unused
        }

        return .active
    }

    /// True if any consecutive pair of charges in the history
    /// differs by more than `tolerance` (relative to the earlier
    /// value). Captures sneaky price hikes the user didn't notice.
    static func hasPriceJump(history: [ChargeHistoryPoint], tolerance: Double) -> Bool {
        guard history.count >= 2 else { return false }
        for i in 1 ..< history.count {
            let prev = NSDecimalNumber(decimal: history[i - 1].amount).doubleValue
            let curr = NSDecimalNumber(decimal: history[i].amount).doubleValue
            guard prev > 0 else { continue }
            let delta = abs(curr - prev) / prev
            if delta > tolerance { return true }
        }
        return false
    }

    // MARK: - Charge history

    static func chargeHistory(
        for ids: [String],
        in transactions: [Transaction]
    ) -> [ChargeHistoryPoint] {
        let lookup = Set(ids)
        let pts = transactions
            .filter { lookup.contains($0.id) }
            .compactMap { tx -> ChargeHistoryPoint? in
                guard let amount = tx.amount else { return nil }
                let positive: Decimal = amount < 0 ? -amount : amount
                return ChargeHistoryPoint(id: tx.id, date: tx.date, amount: positive)
            }
            .sorted { $0.date < $1.date }
        return pts
    }

    // MARK: - Utility filter

    static func matchesUtility(
        merchant: String,
        transactionIds: [String],
        in transactions: [Transaction]
    ) -> Bool {
        let upperMerchant = merchant.uppercased()
        if utilityExclusions.contains(where: { upperMerchant.contains($0) }) {
            return true
        }
        let lookup = Set(transactionIds)
        for tx in transactions where lookup.contains(tx.id) {
            let candidate = (tx.merchantName ?? tx.name).uppercased()
            if utilityExclusions.contains(where: { candidate.contains($0) }) {
                return true
            }
        }
        return false
    }
}
