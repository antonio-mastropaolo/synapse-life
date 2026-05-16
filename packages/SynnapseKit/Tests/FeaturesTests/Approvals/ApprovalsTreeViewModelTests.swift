import Foundation
import Testing
@testable import Models
@testable import Features

private func bundle() -> ApprovalsBundle {
    let approvals = [
        Approval(
            id: "A", title: "A", vendor: nil, approver: "j",
            approverRole: "admin-coordinator", category: "ai-tools",
            requestedAt: Date(timeIntervalSince1970: 1_739_000_000),
            validUntil: nil, status: .approved,
            workdayURL: URL(string: "https://wd5.myworkday.com/wm/d/inst/1/expense"),
            totalAmount: Decimal(100), currency: "USD"
        ),
        Approval(
            id: "B", title: "B", vendor: nil, approver: "j",
            approverRole: "admin-coordinator", category: "ai-tools",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            validUntil: nil, status: .pending,
            workdayURL: nil, totalAmount: nil, currency: nil
        ),
        Approval(
            id: "C", title: "C", vendor: nil, approver: "j",
            approverRole: "admin-coordinator", category: "ai-tools",
            requestedAt: Date(timeIntervalSince1970: 1_710_000_000),
            validUntil: nil, status: .approved,
            workdayURL: nil, totalAmount: nil, currency: nil
        )
    ]
    let receipts = [
        Receipt(id: "r-a-1", approvalId: "A", vendor: "x", amount: 60, currency: "USD",
                date: "2026-02-01", documentKind: .receipt, sourceAccount: "x", submissionStatus: "pending"),
        Receipt(id: "r-a-2", approvalId: "A", vendor: "x", amount: 40, currency: "USD",
                date: "2026-02-03", documentKind: .receipt, sourceAccount: "x", submissionStatus: "pending"),
        Receipt(id: "r-a-inv", approvalId: "A", vendor: "x", amount: 999, currency: "USD",
                date: "2026-02-04", documentKind: .invoice, sourceAccount: "x", submissionStatus: "skipped"),
        Receipt(id: "r-orphan", approvalId: nil, vendor: "y", amount: 10, currency: "USD",
                date: "2026-04-01", documentKind: .receipt, sourceAccount: "x", submissionStatus: "pending")
    ]
    return ApprovalsBundle(approvals: approvals, receipts: receipts)
}

@Suite("ApprovalsTreeViewModel")
@MainActor
struct ApprovalsTreeViewModelTests {

    @Test
    func refreshBuildsDeterministicTree() async {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(bundle())
        let vm = ApprovalsTreeViewModel(api: mock)
        await vm.refresh()
        // 3 approvals + 1 orphan = 4 top-level nodes; newest first by requestedAt.
        #expect(vm.nodes.count == 4)
        if case .approval(let first, _) = vm.nodes[0] {
            #expect(first.id == "A") // most recent timestamp
        }
        // Last node is the orphan.
        if case .unattached(let r) = vm.nodes.last! {
            #expect(r.id == "r-orphan")
        } else {
            Issue.record("expected last to be orphan")
        }
    }

    @Test
    func expansionStateSurvivesRefresh() async {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(bundle())
        let vm = ApprovalsTreeViewModel(api: mock)
        await vm.refresh()
        vm.toggle("A")
        vm.toggle("C")
        #expect(vm.isExpanded("A"))
        #expect(vm.isExpanded("C"))

        // Now refresh again — expansion must persist by id.
        await mock.setNextBundle(bundle())
        await vm.refresh()
        #expect(vm.isExpanded("A"))
        #expect(vm.isExpanded("C"))
        #expect(!vm.isExpanded("B"))
    }

    @Test
    func expandAllAndCollapseAll() async {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(bundle())
        let vm = ApprovalsTreeViewModel(api: mock)
        await vm.refresh()
        vm.expandAll()
        #expect(vm.isExpanded("A"))
        #expect(vm.isExpanded("B"))
        #expect(vm.isExpanded("C"))
        vm.collapseAll()
        #expect(!vm.isExpanded("A"))
        #expect(!vm.isExpanded("B"))
        #expect(!vm.isExpanded("C"))
    }

    @Test
    func inspectorExposesReceiptsTotalAndWorkdayURL() async {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(bundle())
        let vm = ApprovalsTreeViewModel(api: mock)
        await vm.refresh()
        let a = vm.bundle.approvals.first(where: { $0.id == "A" })!
        let inspector = vm.inspector(for: a)
        // Invoice row must be excluded from the inspector total.
        #expect(inspector.receiptsAttached.map(\.id) == ["r-a-1", "r-a-2"])
        #expect(inspector.totalAmount == Decimal(100))
        #expect(inspector.workdayURL?.host == "wd5.myworkday.com")
        #expect(inspector.status == .approved)
    }

    @Test
    func inspectorOnApprovalWithoutReceiptsFallsBackToApprovalAmount() async {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(bundle())
        let vm = ApprovalsTreeViewModel(api: mock)
        await vm.refresh()
        let b = vm.bundle.approvals.first(where: { $0.id == "B" })!
        let inspector = vm.inspector(for: b)
        #expect(inspector.receiptsAttached.isEmpty)
        // B has totalAmount=nil; inspector falls back to approval.totalAmount (also nil).
        #expect(inspector.totalAmount == nil)
        #expect(inspector.workdayURL == nil)
    }

    @Test
    func selectionRoundTrips() async {
        let mock = MockApprovalsAPI()
        await mock.setNextBundle(bundle())
        let vm = ApprovalsTreeViewModel(api: mock)
        await vm.refresh()
        let a = vm.bundle.approvals.first(where: { $0.id == "A" })!
        vm.select(a)
        #expect(vm.selected?.id == "A")
    }
}
