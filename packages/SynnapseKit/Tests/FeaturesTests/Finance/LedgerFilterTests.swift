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
    category: TransactionCategory = .unknown,
    pending: Bool = false
) -> Transaction {
    Transaction(
        id: id, accountId: accountId, accountName: nil,
        amount: amount, currency: "USD",
        date: date, name: name, merchantName: merchant,
        category: category, subcategory: nil, pending: pending
    )
}

private func account(
    id: String,
    institution: String? = "Bank of America",
    name: String = "Adv Plus Banking",
    mask: String? = "4223"
) -> FinanceAccount {
    FinanceAccount(
        id: id, institutionId: nil, institutionName: institution,
        name: name, officialName: nil, mask: mask,
        kind: .checking, currency: "USD",
        currentBalance: nil, availableBalance: nil,
        limitAmount: nil, balanceCapturedAt: nil
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
    func showPendingFalseHidesPendingRows() {
        let rows: [Transaction] = [
            txn(id: "posted", amount: Decimal(-5), date: ref, pending: false),
            txn(id: "pending", amount: Decimal(-5), date: ref, pending: true)
        ]
        var f = LedgerFilter()
        f.showPending = false
        #expect(f.apply(to: rows).map(\.id) == ["posted"])
    }

    @Test
    func showPendingTrueKeepsPendingRows() {
        let rows: [Transaction] = [
            txn(id: "posted", amount: Decimal(-5), date: ref, pending: false),
            txn(id: "pending", amount: Decimal(-5), date: ref, pending: true)
        ]
        let f = LedgerFilter() // default showPending = true
        #expect(f.apply(to: rows).map(\.id) == ["posted", "pending"])
    }

    @Test
    func groupByCardProducesSectionsInAccountOrder() {
        let acctA = account(id: "a", institution: "Chase", name: "Total Checking", mask: "1111")
        let acctB = account(id: "b", institution: "Amex", name: "Gold", mask: "2222")
        let rows: [Transaction] = [
            txn(id: "b1", amount: Decimal(-1), date: ref, accountId: "b"),
            txn(id: "a1", amount: Decimal(-1), date: ref, accountId: "a"),
            txn(id: "a2", amount: Decimal(-1), date: ref.addingTimeInterval(60), accountId: "a")
        ]
        let groups = LedgerFilter().groupByCard(rows: rows, accounts: [acctA, acctB])
        #expect(groups.map(\.account.id) == ["a", "b"])
        // Within each section: newest-first.
        #expect(groups[0].transactions.map(\.id) == ["a2", "a1"])
        #expect(groups[1].transactions.map(\.id) == ["b1"])
    }

    @Test
    func groupByCardOmitsEmptySections() {
        let acctA = account(id: "a")
        let acctB = account(id: "b")
        let rows: [Transaction] = [
            txn(id: "a1", amount: Decimal(-1), date: ref, accountId: "a")
        ]
        let groups = LedgerFilter().groupByCard(rows: rows, accounts: [acctA, acctB])
        #expect(groups.map(\.account.id) == ["a"])
    }

    @Test
    func groupByCardComposesWithCategoryFilter() {
        let acctA = account(id: "a")
        let acctB = account(id: "b")
        let rows: [Transaction] = [
            txn(id: "food-a", amount: Decimal(-1), date: ref,
                accountId: "a", category: .knownCategory("Food & Drink")),
            txn(id: "uber-a", amount: Decimal(-1), date: ref,
                accountId: "a", category: .knownCategory("Transportation")),
            txn(id: "uber-b", amount: Decimal(-1), date: ref,
                accountId: "b", category: .knownCategory("Transportation"))
        ]
        var f = LedgerFilter()
        f.categories = ["Food & Drink"]
        let groups = f.groupByCard(rows: rows, accounts: [acctA, acctB])
        // Only acctA has a Food & Drink row, acctB section disappears.
        #expect(groups.map(\.account.id) == ["a"])
        #expect(groups[0].transactions.map(\.id) == ["food-a"])
    }

    @Test
    func groupByCardComposesWithSearchTextCaseInsensitively() {
        let acctA = account(id: "a")
        let rows: [Transaction] = [
            txn(id: "1", amount: Decimal(-1), date: ref,
                name: "BLUE BOTTLE", accountId: "a"),
            txn(id: "2", amount: Decimal(-1), date: ref,
                name: "PHILZ", accountId: "a")
        ]
        var f = LedgerFilter()
        f.searchText = "bottle"
        let groups = f.groupByCard(rows: rows, accounts: [acctA])
        #expect(groups.flatMap { $0.transactions }.map(\.id) == ["1"])
    }

    @Test
    func groupByCardComposesWithShowPendingToggle() {
        let acctA = account(id: "a")
        let rows: [Transaction] = [
            txn(id: "posted", amount: Decimal(-1), date: ref, accountId: "a"),
            txn(id: "pending", amount: Decimal(-1), date: ref,
                accountId: "a", pending: true)
        ]
        var f = LedgerFilter()
        f.showPending = false
        let groups = f.groupByCard(rows: rows, accounts: [acctA])
        #expect(groups.flatMap { $0.transactions }.map(\.id) == ["posted"])
    }

    @Test
    func groupByCardDropsRowsWithNoMatchingAccount() {
        // Defensive: a row referencing an unknown accountId should not
        // create a phantom section.
        let acctA = account(id: "a")
        let rows: [Transaction] = [
            txn(id: "orphan", amount: Decimal(-1), date: ref, accountId: "zzz"),
            txn(id: "a1", amount: Decimal(-1), date: ref, accountId: "a")
        ]
        let groups = LedgerFilter().groupByCard(rows: rows, accounts: [acctA])
        #expect(groups.map(\.account.id) == ["a"])
        #expect(groups[0].transactions.map(\.id) == ["a1"])
    }

    @Test
    func cardSectionTitleUsesInstitutionAndMask() {
        let acct = account(id: "a", institution: "Bank of America",
                           name: "Adv Plus", mask: "4223")
        #expect(acct.cardSectionTitle == "Bank of America •• 4223")
    }

    @Test
    func cardSectionTitleFallsBackToAccountNameWhenInstitutionMissing() {
        let acct = account(id: "a", institution: nil, name: "House Account", mask: "0001")
        #expect(acct.cardSectionTitle == "House Account •• 0001")
    }

    @Test
    func cardSectionTitleOmitsMaskSuffixWhenAbsent() {
        let acct = account(id: "a", institution: "Fidelity",
                           name: "Brokerage", mask: nil)
        #expect(acct.cardSectionTitle == "Fidelity")
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
