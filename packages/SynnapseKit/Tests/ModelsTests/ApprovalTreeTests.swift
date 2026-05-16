import Foundation
import Testing
@testable import Models

private func approval(_ id: String, daysAgo: Int) -> Approval {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    return Approval(
        id: id,
        title: "Approval \(id)",
        vendor: nil,
        approver: "Jacqulyn",
        approverRole: "admin-coordinator",
        category: "ai-tools",
        requestedAt: now.addingTimeInterval(-Double(daysAgo * 86_400)),
        validUntil: nil,
        status: .approved,
        workdayURL: nil,
        totalAmount: nil,
        currency: nil
    )
}

private func receipt(_ id: String, approval: String?, date: String) -> Receipt {
    Receipt(
        id: id,
        approvalId: approval,
        vendor: "Anthropic",
        amount: 100,
        currency: "USD",
        date: date,
        documentKind: .receipt,
        sourceAccount: "a@b.c",
        submissionStatus: "pending"
    )
}

@Suite("ApprovalTree assembly")
struct ApprovalTreeTests {

    @Test
    func groupsReceiptsUnderTheirApproval() {
        let approvals = [approval("a", daysAgo: 30), approval("b", daysAgo: 10)]
        let receipts = [
            receipt("r1", approval: "a", date: "2026-02-01"),
            receipt("r2", approval: "b", date: "2026-04-01"),
            receipt("r3", approval: "a", date: "2026-02-15")
        ]
        let tree = buildApprovalTree(approvals: approvals, receipts: receipts)

        // Newest approval first: "b" was 10 days ago, "a" was 30 days ago.
        #expect(tree.count == 2)
        if case .approval(let first, let firstKids) = tree[0] {
            #expect(first.id == "b")
            #expect(firstKids.map(\.id) == ["r2"])
        } else {
            Issue.record("expected first node to be an approval, got \(tree[0])")
        }
        if case .approval(let second, let secondKids) = tree[1] {
            #expect(second.id == "a")
            // Receipts inside an approval are date-asc.
            #expect(secondKids.map(\.id) == ["r1", "r3"])
        } else {
            Issue.record("expected second node to be an approval, got \(tree[1])")
        }
    }

    @Test
    func unattachedReceiptsLandInOrphanBucket() {
        let approvals = [approval("a", daysAgo: 30)]
        let receipts = [
            receipt("r1", approval: "a", date: "2026-02-01"),
            receipt("r2", approval: nil, date: "2026-03-01"),
            receipt("r3", approval: "MISSING", date: "2026-02-15")
        ]
        let tree = buildApprovalTree(approvals: approvals, receipts: receipts)

        // 1 approval + 2 orphans.
        #expect(tree.count == 3)
        // Orphans are date-asc and come after approvals.
        let orphanIds: [String] = tree.compactMap {
            if case .unattached(let r) = $0 { return r.id } else { return nil }
        }
        #expect(orphanIds == ["r3", "r2"])
    }

    @Test
    func pureFunctionDeterministic() {
        let approvals = [approval("z", daysAgo: 5), approval("y", daysAgo: 5)]
        let receipts = [receipt("r1", approval: "z", date: "2026-02-01")]
        let first = buildApprovalTree(approvals: approvals, receipts: receipts)
        let second = buildApprovalTree(approvals: approvals, receipts: receipts)
        // Identical inputs → identical outputs, including tie-break by id.
        #expect(first == second)
        if case .approval(let a, _) = first[0] { #expect(a.id == "y") }
    }

    @Test
    func emptyInputsProduceEmptyTree() {
        #expect(buildApprovalTree(approvals: [], receipts: []).isEmpty)
    }

    @Test
    func approvalWithNoReceiptsStillAppears() {
        let approvals = [approval("solo", daysAgo: 1)]
        let tree = buildApprovalTree(approvals: approvals, receipts: [])
        #expect(tree.count == 1)
        if case .approval(let a, let kids) = tree[0] {
            #expect(a.id == "solo")
            #expect(kids.isEmpty)
        }
    }
}
