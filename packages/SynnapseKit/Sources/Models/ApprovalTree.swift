import Foundation

/// One node in the approvals tree. Either a real approval (with its attached
/// receipts as children, ordered oldest receipt first) or a receipt that
/// references a missing/absent approval (the "unattached" bucket).
public enum ApprovalTreeNode: Sendable, Equatable, Identifiable, Hashable {
    case approval(Approval, children: [Receipt])
    case unattached(Receipt)

    public var id: String {
        switch self {
        case .approval(let approval, _):
            return "ap:\(approval.id)"
        case .unattached(let receipt):
            return "or:\(receipt.id)"
        }
    }
}

/// Build the approvals tree from a flat (approvals, receipts) bundle. Pure;
/// deterministic; no I/O.
///
/// Ordering rules:
///  - Real approvals first, newest `requestedAt` first; tie-broken by id.
///  - Within an approval, receipts sorted by `date` ascending (oldest first)
///    so the chronological audit reads top-down; tie-broken by id.
///  - Unattached receipts trail the real approvals, also sorted by `date` asc.
///
/// Defensiveness: receipts that reference an `approvalId` not present in the
/// supplied approvals list are treated as unattached. There is no recursion in
/// this graph (receipts never point at receipts) — cycles are impossible by
/// schema, but the implementation is still single-pass and bounded.
public func buildApprovalTree(approvals: [Approval], receipts: [Receipt]) -> [ApprovalTreeNode] {
    let approvalsById = Dictionary(uniqueKeysWithValues: approvals.map { ($0.id, $0) })

    var groupedByApproval: [String: [Receipt]] = [:]
    var orphans: [Receipt] = []
    for receipt in receipts {
        if let approvalId = receipt.approvalId,
           approvalsById[approvalId] != nil {
            groupedByApproval[approvalId, default: []].append(receipt)
        } else {
            orphans.append(receipt)
        }
    }

    let sortedApprovals = approvals.sorted { lhs, rhs in
        if lhs.requestedAt != rhs.requestedAt {
            return lhs.requestedAt > rhs.requestedAt
        }
        return lhs.id < rhs.id
    }

    var nodes: [ApprovalTreeNode] = []
    nodes.reserveCapacity(sortedApprovals.count + orphans.count)
    for approval in sortedApprovals {
        let children = (groupedByApproval[approval.id] ?? []).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id < rhs.id
        }
        nodes.append(.approval(approval, children: children))
    }

    let sortedOrphans = orphans.sorted { lhs, rhs in
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.id < rhs.id
    }
    for orphan in sortedOrphans {
        nodes.append(.unattached(orphan))
    }
    return nodes
}
