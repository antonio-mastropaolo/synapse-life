import Foundation
import Testing
@testable import Models
@testable import Features

/// Behaviour for the iOS Transactions tab segmented control + grouping.
/// These reducers must stay pure so the SwiftUI surface can call them
/// on every keystroke / picker change without locking; this suite locks
/// the contract.
@Suite("Ledger status scope + card grouping")
struct LedgerStatusScopeTests {

    private func sample() -> [Models.Transaction] {
        let day = Date(timeIntervalSince1970: 1_739_625_600)
        return [
            Models.Transaction(
                id: "a", accountId: "chk", accountName: "Chase Checking",
                amount: -5, currency: "USD", date: day,
                name: "Starbucks", merchantName: nil,
                category: .knownCategory("FOOD"), subcategory: nil, pending: false
            ),
            Models.Transaction(
                id: "b", accountId: "chk", accountName: "Chase Checking",
                amount: -42, currency: "USD", date: day,
                name: "Whole Foods", merchantName: nil,
                category: .knownCategory("FOOD"), subcategory: nil, pending: true
            ),
            Models.Transaction(
                id: "c", accountId: "cc", accountName: "Sapphire",
                amount: -999, currency: "USD", date: day,
                name: "Apple", merchantName: nil,
                category: .knownCategory("ELECTRONICS"), subcategory: nil, pending: false
            ),
            Models.Transaction(
                id: "d", accountId: nil, accountName: nil,
                amount: 12, currency: "USD", date: day,
                name: "Refund", merchantName: nil,
                category: .knownCategory("REFUND"), subcategory: nil, pending: false
            )
        ]
    }

    @Test
    func allScopeIsIdentity() {
        let rows = sample()
        #expect(LedgerStatusScope.all.apply(to: rows) == rows)
    }

    @Test
    func pendingScopeKeepsOnlyPending() {
        let rows = sample()
        let filtered = LedgerStatusScope.pending.apply(to: rows)
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "b")
    }

    @Test
    func postedScopeDropsPending() {
        let rows = sample()
        let filtered = LedgerStatusScope.posted.apply(to: rows)
        #expect(filtered.count == 3)
        #expect(!filtered.contains { $0.pending })
    }

    @Test
    func groupingKeysOnAccountName() {
        let sections = groupTransactionsByCard(sample())
        // Chase Checking, Sapphire, Unknown — sorted lexicographically.
        let keys = sections.map(\.card)
        #expect(keys == ["Chase Checking", "Sapphire", "Unknown"])
    }

    @Test
    func groupingFallsBackToAccountIdThenUnknown() {
        let day = Date()
        let rows: [Models.Transaction] = [
            // No accountName — should land in the accountId bucket "x".
            Models.Transaction(
                id: "1", accountId: "x", accountName: nil,
                amount: 1, currency: "USD", date: day,
                name: "row", merchantName: nil,
                category: .knownCategory("X"), subcategory: nil, pending: false
            ),
            // No accountName, no accountId — Unknown bucket.
            Models.Transaction(
                id: "2", accountId: nil, accountName: nil,
                amount: 1, currency: "USD", date: day,
                name: "row", merchantName: nil,
                category: .knownCategory("X"), subcategory: nil, pending: false
            )
        ]
        let sections = groupTransactionsByCard(rows)
        let keys = sections.map(\.card)
        #expect(keys == ["Unknown", "x"])
    }

    @Test
    func emptyInputProducesEmptySections() {
        #expect(groupTransactionsByCard([]).isEmpty)
    }
}
