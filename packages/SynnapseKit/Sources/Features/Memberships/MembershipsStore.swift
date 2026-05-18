import Foundation
import Observation
import Models

/// Single source of truth for the Memberships tab.
///
/// Pure-logic detection + optimisation run synchronously on the main
/// thread because the inputs are small (≤ a few hundred transactions
/// in v1 demo / live mode) and the detector itself runs in well under
/// a millisecond. The async `enrichGuidesInBackground()` slot is
/// reserved for the LLM-powered cancellation-guide generation that
/// lands in a follow-up commit — calling it today is a deliberate
/// no-op so the integration shape exists.
@MainActor
@Observable
public final class MembershipsStore {

    public private(set) var memberships: [Membership] = []
    public private(set) var optimizationSummary: OptimizationSummary?
    public private(set) var duplicateClusters: [DuplicateCluster] = []
    public private(set) var lastRefreshed: Date?

    private let usesSampleData: Bool

    public init(usesSampleData: Bool = false) {
        self.usesSampleData = usesSampleData
        if usesSampleData {
            hydrateFromSampleData()
        }
    }

    // MARK: - Refresh

    /// Re-run the detector + optimiser against the supplied
    /// transactions. Called from `AppModel.refreshIntelligenceSurfaces`
    /// after the live transaction feed has been hydrated.
    public func refresh(
        transactions: [Transaction],
        today: Date = Date()
    ) {
        let detected = MembershipDetector.detect(
            transactions: transactions,
            today: today
        )
        applyOptimization(to: detected)
        lastRefreshed = today
    }

    /// Slot reserved for the LLM-generated cancellation guide pass.
    /// V1 is a no-op so the call site exists today and a future
    /// commit can swap in the live implementation without touching
    /// `SynnapseMacApp.swift`.
    public func enrichGuidesInBackground() async {
        // Intentional no-op for v1.
    }

    // MARK: - Internal helpers

    /// Run the optimiser and store the decorated set.
    private func applyOptimization(to memberships: [Membership]) {
        let (tips, clusters, summary) = MembershipOptimizer.optimize(memberships: memberships)

        // Re-bind tips back onto the matching `Membership` so the
        // detail view doesn't have to look them up by id.
        let tipsByMerchantID = Dictionary(grouping: tips, by: \.merchantId)
        self.memberships = memberships.map { m in
            guard let related = tipsByMerchantID[m.id], !related.isEmpty else { return m }
            return Membership(
                id: m.id,
                merchant: m.merchant,
                monthlyCost: m.monthlyCost,
                annualCost: m.annualCost,
                currency: m.currency,
                cadenceDays: m.cadenceDays,
                firstSeenAt: m.firstSeenAt,
                lastChargedAt: m.lastChargedAt,
                nextExpectedAt: m.nextExpectedAt,
                occurrenceCount: m.occurrenceCount,
                status: m.status,
                logoDomain: m.logoDomain,
                sourceTransactionIds: m.sourceTransactionIds,
                cancellationGuide: m.cancellationGuide,
                optimizationTips: related.sorted {
                    $0.estimatedSavingsMonthly > $1.estimatedSavingsMonthly
                },
                chargeHistory: m.chargeHistory,
                confidence: m.confidence,
                isSample: m.isSample
            )
        }
        self.duplicateClusters = clusters
        self.optimizationSummary = summary
    }

    /// Seed the store from `MembershipsDemoData`. Used when the app
    /// boots in demo mode so the surface isn't empty before any live
    /// transactions exist.
    private func hydrateFromSampleData() {
        let sample = MembershipsDemoData.sampleMemberships()
        applyOptimization(to: sample)
        lastRefreshed = Date()
    }

    // MARK: - Derived helpers (used by the views)

    /// Sum of all monthly costs across the current `memberships`.
    public var totalMonthly: Decimal {
        memberships.reduce(Decimal.zero) { $0 + $1.monthlyCost }
    }

    /// Sum of all annual-equivalent costs (totalMonthly * 12).
    public var totalAnnual: Decimal {
        totalMonthly * 12
    }
}
