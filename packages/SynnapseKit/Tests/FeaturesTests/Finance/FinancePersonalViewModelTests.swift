import Foundation
import SwiftUI
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func sampleAccounts() -> [FinanceAccount] {
    [
        FinanceAccount(
            id: "cash", institutionId: "ins_chase", institutionName: "Chase",
            name: "Total Checking", officialName: nil, mask: "1234",
            kind: .checking, currency: "USD",
            currentBalance: Decimal(string: "12345.67"),
            availableBalance: nil, limitAmount: nil, balanceCapturedAt: nil
        ),
        FinanceAccount(
            id: "brk", institutionId: "ins_fidelity", institutionName: "Fidelity",
            name: "Brokerage", officialName: nil, mask: "5678",
            kind: .brokerage, currency: "USD",
            currentBalance: Decimal(50_000),
            availableBalance: nil, limitAmount: nil, balanceCapturedAt: nil
        ),
        FinanceAccount(
            id: "cc", institutionId: "ins_chase", institutionName: "Chase",
            name: "Sapphire", officialName: nil, mask: "0001",
            kind: .credit, currency: "USD",
            currentBalance: Decimal(1_500),
            availableBalance: nil, limitAmount: nil, balanceCapturedAt: nil
        )
    ]
}

@MainActor
@Suite("FinancePersonalViewModel")
struct FinancePersonalViewModelTests {

    @Test
    func startsIdleAndTransitionsToReadyOnRefresh() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        let vm = FinancePersonalViewModel(api: api)
        if case .idle = vm.state {} else {
            Issue.record("expected idle initial state")
        }
        await vm.refresh()
        if case .ready(let snapshot) = vm.state {
            #expect(snapshot.accounts.count == 3)
            #expect(snapshot.netWorth == Decimal(60_845) + Decimal(string: "0.67")!)
        } else {
            Issue.record("expected ready, got \(vm.state)")
        }
    }

    @Test
    func errorStateIsExposedOnAPIFailure() async {
        let api = MockFinanceAPI()
        await api.setNextError(APIError.server(status: 500))
        let vm = FinancePersonalViewModel(api: api)
        await vm.refresh()
        if case .error = vm.state {} else {
            Issue.record("expected error, got \(vm.state)")
        }
    }

    @Test
    func concealBalancesFlipsWhenScenePhaseLeavesActive() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        let vm = FinancePersonalViewModel(api: api)
        #expect(vm.concealBalances == false)
        // scenePhase != .active → conceal
        vm.scenePhaseDidChange(.inactive)
        #expect(vm.concealBalances == true)
        vm.scenePhaseDidChange(.background)
        #expect(vm.concealBalances == true)
        vm.scenePhaseDidChange(.active)
        #expect(vm.concealBalances == false)
    }

    @Test
    func selectingAccountExposesPerAccountTransactionsVM() async {
        let api = MockFinanceAPI()
        await api.setAccounts(sampleAccounts())
        let vm = FinancePersonalViewModel(api: api)
        await vm.refresh()
        let cash = sampleAccounts()[0]
        let perAccount = vm.transactionsViewModel(for: cash)
        #expect(perAccount.accountId == "cash")
    }
}
