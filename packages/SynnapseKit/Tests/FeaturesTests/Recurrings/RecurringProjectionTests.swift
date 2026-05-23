import Foundation
import Testing
@testable import Models
@testable import Features

/// G3 — the `DetectedRecurring -> Recurring` bridge. Pins the slug-based id
/// (debit vs income namespaces), the category-slug collapse, and that the
/// numeric fields pass through untouched so the persisted store and the agent
/// tool see the same figures the detector computed.
@Suite("RecurringProjection")
struct RecurringProjectionTests {

    private func detected(merchant: String, category: CategoryID) -> DetectedRecurring {
        DetectedRecurring(
            merchant: merchant,
            category: category,
            medianAmount: Decimal(string: "12.99")!,
            cadenceDays: 30,
            lastSeen: Date(timeIntervalSince1970: 1_777_000_000),
            predictedNext: Date(timeIntervalSince1970: 1_779_592_000),
            occurrenceCount: 4,
            confidence: 0.83,
            transactionIds: ["a", "b", "c", "d"]
        )
    }

    @Test
    func debitProjectionUsesPlainSlugId() {
        let r = detected(merchant: "Spotify Premium", category: .subscriptions).asRecurring()
        #expect(r.id == "recurring.spotify-premium")
        #expect(r.category == "subscriptions")
        #expect(r.merchant == "Spotify Premium")
        #expect(r.medianAmount == Decimal(string: "12.99")!)
        #expect(r.cadenceDays == 30)
        #expect(r.occurrenceCount == 4)
        #expect(r.confidence == 0.83)
        #expect(r.transactionIds == ["a", "b", "c", "d"])
        #expect(r.isIncome == false)
    }

    @Test
    func incomeProjectionUsesDistinctIdNamespace() {
        let debit = detected(merchant: "Acme", category: .transfers).asRecurring(isIncome: false)
        let income = detected(merchant: "Acme", category: .income).asRecurring(isIncome: true)
        #expect(debit.id == "recurring.acme")
        #expect(income.id == "recurring.income.acme")
        #expect(income.isIncome == true)
        #expect(income.category == "income")
        // Distinct ids mean a recurring credit never overwrites a recurring
        // debit of the same merchant in the store.
        #expect(debit.id != income.id)
    }
}
