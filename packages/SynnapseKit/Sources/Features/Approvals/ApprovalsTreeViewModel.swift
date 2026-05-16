import Foundation
import Observation
import Models

public enum ApprovalsTreeState: Sendable, Equatable {
    case idle
    case loading
    case results([ApprovalTreeNode])
    case empty
    case error(String)
}

/// Inspector projection for the currently-selected approval. Computed by
/// `ApprovalsTreeViewModel.inspector(for:)` — drives the right-hand pane on
/// macOS and the detail screen on iOS. The Workday URL is presented as a
/// read-only deeplink; per memory `feedback_workday_no_terminal_clicks` the
/// native client never auto-submits.
public struct ApprovalInspectorPayload: Sendable, Equatable {
    public let approval: Approval
    public let receiptsAttached: [Receipt]
    public let totalAmount: Decimal?
    public let currency: String?
    public let status: ApprovalStatus
    public let workdayURL: URL?

    public init(
        approval: Approval,
        receiptsAttached: [Receipt],
        totalAmount: Decimal?,
        currency: String?,
        status: ApprovalStatus,
        workdayURL: URL?
    ) {
        self.approval = approval
        self.receiptsAttached = receiptsAttached
        self.totalAmount = totalAmount
        self.currency = currency
        self.status = status
        self.workdayURL = workdayURL
    }
}

/// Tree-view-specific view model. Holds expansion state by stable
/// approval id so a `refresh()` doesn't collapse the user's open nodes.
@MainActor
@Observable
public final class ApprovalsTreeViewModel {
    public private(set) var state: ApprovalsTreeState = .idle
    public private(set) var bundle: ApprovalsBundle = ApprovalsBundle(approvals: [], receipts: [])
    public private(set) var nodes: [ApprovalTreeNode] = []
    public private(set) var expanded: Set<Approval.ID> = []
    public var selected: Approval?

    private let api: ApprovalsAPI

    public init(api: ApprovalsAPI) {
        self.api = api
    }

    public func refresh() async {
        state = .loading
        do {
            let response = try await api.list(ifNoneMatch: nil)
            if let bundle = response.bundle {
                self.bundle = bundle
                self.nodes = buildApprovalTree(
                    approvals: bundle.approvals,
                    receipts: bundle.receipts
                )
            }
            state = nodes.isEmpty ? .empty : .results(nodes)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func toggle(_ approvalId: Approval.ID) {
        if expanded.contains(approvalId) {
            expanded.remove(approvalId)
        } else {
            expanded.insert(approvalId)
        }
    }

    public func expandAll() {
        for node in nodes {
            if case .approval(let approval, _) = node {
                expanded.insert(approval.id)
            }
        }
    }

    public func collapseAll() {
        expanded.removeAll()
    }

    public func isExpanded(_ approvalId: Approval.ID) -> Bool {
        expanded.contains(approvalId)
    }

    public func select(_ approval: Approval) {
        selected = approval
    }

    public func inspector(for approval: Approval) -> ApprovalInspectorPayload {
        let attached = bundle.receipts
            .filter { $0.approvalId == approval.id && $0.documentKind.isBundleable }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
        let total = attached.reduce(Decimal.zero) { acc, receipt in
            acc + (receipt.amount ?? Decimal.zero)
        }
        let currency = attached.first?.currency ?? approval.currency
        return ApprovalInspectorPayload(
            approval: approval,
            receiptsAttached: attached,
            totalAmount: attached.isEmpty ? approval.totalAmount : total,
            currency: currency,
            status: approval.status,
            workdayURL: approval.workdayURL
        )
    }

    /// Test-only seam.
    public func injectForSnapshots(bundle: ApprovalsBundle, expandAll: Bool = false) {
        self.bundle = bundle
        self.nodes = buildApprovalTree(
            approvals: bundle.approvals,
            receipts: bundle.receipts
        )
        if expandAll { self.expandAll() }
        self.state = nodes.isEmpty ? .empty : .results(nodes)
    }

    public func injectExpanded(_ ids: Set<Approval.ID>) {
        self.expanded = ids
    }
}
