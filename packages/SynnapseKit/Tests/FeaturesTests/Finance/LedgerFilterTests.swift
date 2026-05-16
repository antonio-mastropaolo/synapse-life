import Foundation
import Testing
@testable import Models
@testable import Features

private func txn(
    id: String,
    amount: Decimal,
    date: Date,
    name: String = "n",
    merchant: String? = nil,
    accountId: String = "a",
    category: TransactionCategory = .unknown
) -> Transaction {
    Transaction(
        id: id, accountId: accountId, accountName: nil,
        amount: amount, currency: "USD",
        date: date, name: name, merchantName: merchant,
        category: category, subcategory: nil, pending: false
    )
}

@Suite("LedgerFilter")
struct LedgerFilterTests {

    private let ref = Date(timeIntervalSince1970: 1_734_652_800) // 2024-12-20

    @Test
    func emptyFilterReturnsInputUnchanged() {
        let rows: [Transaction] = [
            txn(id: "t1", amount: Decimal(-10), date: ref),
            txn(id: "t2", amount: Decimal(20), date: ref)
        ]
        let filtered = LedgerFilter().apply(to: rows)
        #expect(filtered.map(\.id) == rows.map(\.id))
    }

    @Test
    func dateRangeFiltersOutsideBounds() {
        let early = ref.addingTimeInterval(-7 * 86_400)
        let late = ref.addingTimeInterval(7 * 86_400)
        let rows: [Transaction] = [
            txn(id: "old", amount: Decimal(1), date: early),
            txn(id: "now", amount: Decimal(1), date: ref),
            txn(id: "new", amount: Decimal(1), date: late)
        ]
        var f = LedgerFilter()
        f.dateRange = ref.addingTimeInterval(-1 * 86_400)...ref.addingTimeInterval(1 * 86_400)
        let filtered = f.apply(to: rows)
        #expect(filtered.map(\.id) == ["now"])
    }

    @Test
    func accountFilterExactMatch() {
        let rows: [Transaction] = [
            txn(id: "1", amount: Decimal(1), date: ref, accountId: "cash"),
            txn(id: "2", amount: Decimal(1), date: ref, accountId: "credit")
        ]
        var f = LedgerFilter()
        f.accountIds = ["cash"]
        #expect(f.apply(to: rows).map(\.id) == ["1"])
    }

    @Test
    func categoryFilterMatchesKnownCategoryString() {
        let rows: [Transaction] = [
            txn(id: "food", amount: Decimal(-5), date: ref, category: .knownCategory("Food & Drink")),
            txn(id: "uber", amount: Decimal(-5), date: ref, category: .knownCategory("Transportation"))
        ]
        var f = LedgerFilter()
        f.categories = ["Food & Drink"]
        #expect(f.apply(to: rows).map(\.id) == ["food"])
    }

    @Test
    func searchTextMatchesNameAndMerchantCaseInsensitive() {
        let rows: [Transaction] = [
            txn(id: "1", amount: Decimal(1), date: ref, name: "BLUE BOTTLE", merchant: "Blue Bottle"),
            txn(id: "2", amount: Decimal(1), date: ref, name: "PHILZ", merchant: "Philz Coffee")
        ]
        var f = LedgerFilter()
        f.searchText = "bottle"
        #expect(f.apply(to: rows).map(\.id) == ["1"])
    }

    @Test
    func composedFiltersApplyAllPredicates() {
        let rows: [Transaction] = [
            txn(id: "match", amount: Decimal(-5), date: ref,
                name: "Latte", accountId: "cash",
                category: .knownCategory("Food & Drink")),
            txn(id: "wrong-account", amount: Decimal(-5), date: ref,
                name: "Latte", accountId: "credit",
                category: .knownCategory("Food & Drink")),
            txn(id: "wrong-category", amount: Decimal(-5), date: ref,
                name: "Latte", accountId: "cash",
                category: .knownCategory("Transportation"))
        ]
        var f = LedgerFilter()
        f.accountIds = ["cash"]
        f.categories = ["Food & Drink"]
        f.searchText = "latte"
        #expect(f.apply(to: rows).map(\.id) == ["match"])
    }

    @Test
    func filterIsDeterministicAndStable() {
        // Same filter applied twice to the same input yields the same order.
        let rows: [Transaction] = (0..<25).map { i in
            txn(id: "id\(i)", amount: Decimal(i), date: ref.addingTimeInterval(Double(i)))
        }
        var f = LedgerFilter()
        f.searchText = "n"
        let a = f.apply(to: rows).map(\.id)
        let b = f.apply(to: rows).map(\.id)
        #expect(a == b)
    }
}
