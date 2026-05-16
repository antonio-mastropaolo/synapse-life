import Foundation
import Testing
@testable import Models
@testable import Features

private func sampleBundle() -> ApprovalsBundle {
    let approvals = [
        Approval(
            id: "ap-anthropic",
            title: "Anthropic API spend",
            vendor: "Anthropic",
            approver: "Jacqulyn Ledger",
            approverRole: "admin-coordinator",
            category: "ai-tools",
            requestedAt: Date(timeIntervalSince1970: 1_739_625_600),
            validUntil: nil,
            status: .approved,
            workdayURL: nil,
            totalAmount: Decimal(412.55),
            currency: "USD"
        ),
        Approval(
            id: "ap-openai",
            title: "OpenAI API spend",
            vendor: "OpenAI",
            approver: "Jacqulyn Ledger",
            approverRole: "admin-coordinator",
            category: "ai-tools",
            requestedAt: Date(timeIntervalSince1970: 1_730_000_000),
            validUntil: nil,
            status: .pending,
            workdayURL: nil,
            totalAmount: nil,
            currency: nil
        )
    ]
    let receipts = [
        Receipt(
            id: "r1",
            approvalId: "ap-anthropic",
            vendor: "Anthropic",
            amount: 200,
            currency: "USD",
            date: "2026-02-10",
            documentKind: .receipt,
            sourceAccount: "amastropaolo@wm.edu",
            submissionStatus: "pending"
        ),
        Receipt(
            id: "r2",
            approvalId: "ap-anthropic",
            vendor: "Anthropic",
            amount: 212.55,
            currency: "USD",
            date: "2026-03-12",
            documentKind: .invoice,
            sourceAccount: "amastropaolo@wm.edu",
            submissionStatus: "skipped"
        ),
        Receipt(
            id: "r3",
            approvalId: "ap-anthropic",
            vendor: "Anthropic",
            amount: 50,
            currency: "USD",
            date: "2026-02-25",
            documentKind: .receipt,
            sourceAccount: "amastropaolo@wm.edu",
            submissionStatus: "pending"
        )
    ]
    return ApprovalsBundle(approvals: approvals, receipts: receipts)
}

@Suite("ApprovalsViewModel — flat")
@MainActor
struct ApprovalsViewModelTests {

    @Test
    func refreshPopulatesResults() async throws {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(sampleBundle())
        let vm = ApprovalsViewModel(api: mock)
        await vm.refresh()
        if case .results(let rows) = vm.state {
            #expect(rows.count == 2)
        } else {
            Issue.record("expected .results, got \(vm.state)")
        }
    }

    @Test
    func selectionRoundTrips() async throws {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(sampleBundle())
        let vm = ApprovalsViewModel(api: mock)
        await vm.refresh()
        guard case .results(let rows) = vm.state else {
            Issue.record("no results"); return
        }
        vm.select(rows[0])
        #expect(vm.selected?.id == rows[0].id)
        vm.clearSelection()
        #expect(vm.selected == nil)
    }

    @Test
    func searchAndStatusComposeAdditively() async throws {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(sampleBundle())
        let vm = ApprovalsViewModel(api: mock)
        await vm.refresh()

        // Search-only.
        let bySearch = vm.filter(searchText: "openai")
        #expect(bySearch.count == 1)
        #expect(bySearch.first?.id == "ap-openai")

        // Status-only.
        let byStatus = vm.filter(searchText: "", status: .pending)
        #expect(byStatus.count == 1)
        #expect(byStatus.first?.id == "ap-openai")

        // Compose: anthropic + pending should match nothing.
        let composed = vm.filter(searchText: "anthropic", status: .pending)
        #expect(composed.isEmpty)
    }

    @Test
    func emptySearchReturnsAll() async throws {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(sampleBundle())
        let vm = ApprovalsViewModel(api: mock)
        await vm.refresh()
        let all = vm.filter(searchText: "")
        #expect(all.count == 2)
    }

    @Test
    func receiptsForApprovalDropsNonBundleable() async throws {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(sampleBundle())
        let vm = ApprovalsViewModel(api: mock)
        await vm.refresh()
        guard let anthropic = vm.bundle.approvals.first(where: { $0.id == "ap-anthropic" }) else {
            Issue.record("missing fixture"); return
        }
        let kids = vm.receipts(for: anthropic)
        // Only r1 and r3 (both .receipt); r2 is .invoice and must be hidden.
        #expect(kids.map(\.id) == ["r1", "r3"])
    }
}
