import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private let day0 = Date(timeIntervalSince1970: 1_734_652_800) // 2024-12-20

private func acct(
    _ id: String,
    institution: String = "Bank of America",
    name: String = "Adv Plus",
    mask: String = "4223"
) -> FinanceAccount {
    FinanceAccount(
        id: id, institutionId: nil, institutionName: institution,
        name: name, officialName: nil, mask: mask,
        kind: .checking, currency: "USD",
        currentBalance: nil, availableBalance: nil,
        limitAmount: nil, balanceCapturedAt: nil
    )
}

private func tx(
    _ id: String,
    accountId: String,
    name: String = "Row",
    category: TransactionCategory = .unknown,
    pending: Bool = false,
    offsetDays: Int = 0
) -> Transaction {
    Transaction(
        id: id, accountId: accountId, accountName: nil,
        amount: Decimal(-5), currency: "USD",
        date: day0.addingTimeInterval(Double(offsetDays) * 86_400),
        name: name, merchantName: nil,
        category: category, subcategory: nil, pending: pending
    )
}

private func sampleAccounts() -> [FinanceAccount] {
    [
        acct("cash", institution: "Chase", name: "Total Checking", mask: "1111"),
        acct("cc", institution: "Amex", name: "Gold", mask: "2222")
    ]
}

private func sampleTransactions() -> [Transaction] {
    [
        tx("t1", accountId: "cash", name: "BLUE BOTTLE",
           category: .knownCategory("Food & Drink"), offsetDays: 0),
        tx("t2", accountId: "cash", name: "FRESH MARKET",
           category: .knownCategory("Groceries"), offsetDays: 1),
        tx("t3", accountId: "cc", name: "UBER",
           category: .knownCategory("Transportation"), pending: true, offsetDays: 2),
        tx("t4", accountId: "cash", name: "PAYROLL",
           category: .knownCategory("Income"), offsetDays: 3)
    ]
}

@MainActor
@Suite("FinanceTransactionsViewModel")
struct FinanceTransactionsViewModelTests {

    @Test
    func startsIdleThenReadyAfterRefresh() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        await api.setTransactions(sampleTransactions())
        let vm = FinanceTransactionsViewModel(api: api)
        if case .idle = vm.state {} else {
            Issue.record("expected idle initial state")
        }
        await vm.refresh()
        guard case .ready(let groups) = vm.state else {
            Issue.record("expected ready, got \(vm.state)")
            return
        }
        #expect(groups.map(\.account.id) == ["cash", "cc"])
        // Newest-first within each section.
        #expect(groups[0].transactions.map(\.id) == ["t4", "t2", "t1"])
        #expect(groups[1].transactions.map(\.id) == ["t3"])
    }

    @Test
    func selectingCategoryRegroupsToMatchingRowsOnly() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        await api.setTransactions(sampleTransactions())
        let vm = FinanceTransactionsViewModel(api: api)
        await vm.refresh()
        vm.selectedCategory = "Food & Drink"
        guard case .ready(let groups) = vm.state else {
            Issue.record("expected ready, got \(vm.state)")
            return
        }
        #expect(groups.map(\.account.id) == ["cash"])
        #expect(groups[0].transactions.map(\.id) == ["t1"])
    }

    @Test
    func clearingCategoryReturnsAllSections() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        await api.setTransactions(sampleTransactions())
        let vm = FinanceTransactionsViewModel(api: api)
        await vm.refresh()
        vm.selectedCategory = "Food & Drink"
        vm.selectedCategory = nil
        guard case .ready(let groups) = vm.state else {
            Issue.record("expected ready, got \(vm.state)")
            return
        }
        #expect(groups.count == 2)
    }

    @Test
    func searchFiltersByDescriptionCaseInsensitive() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        await api.setTransactions(sampleTransactions())
        let vm = FinanceTransactionsViewModel(api: api)
        await vm.refresh()
        vm.searchText = "uber"
        guard case .ready(let groups) = vm.state else {
            Issue.record("expected ready, got \(vm.state)")
            return
        }
        #expect(groups.map(\.account.id) == ["cc"])
        #expect(groups[0].transactions.map(\.id) == ["t3"])
    }

    @Test
    func togglingShowPendingOffHidesPendingRows() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        await api.setTransactions(sampleTransactions())
        let vm = FinanceTransactionsViewModel(api: api)
        await vm.refresh()
        vm.showPending = false
        guard case .ready(let groups) = vm.state else {
            Issue.record("expected ready, got \(vm.state)")
            return
        }
        // cc only had one row (t3 / pending), so the whole section drops.
        #expect(groups.map(\.account.id) == ["cash"])
        #expect(groups[0].transactions.allSatisfy { !$0.pending })
    }

    @Test
    func availableCategoriesReflectsCurrentRowSet() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        await api.setTransactions(sampleTransactions())
        let vm = FinanceTransactionsViewModel(api: api)
        await vm.refresh()
        #expect(vm.availableCategories == ["Food & Drink", "Groceries", "Income", "Transportation"])
    }

    @Test
    func errorStateIsSurfacedOnAPIFailure() async {
        let api = MockFinanceAPI()
        await api.setNextError(APIError.server(status: 500))
        let vm = FinanceTransactionsViewModel(api: api)
        await vm.refresh()
        if case .error = vm.state {} else {
            Issue.record("expected error state, got \(vm.state)")
        }
    }
}
