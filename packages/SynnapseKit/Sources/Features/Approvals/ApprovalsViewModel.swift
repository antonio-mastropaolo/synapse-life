import Foundation
import Observation
import Models

public enum ApprovalsState: Sendable, Equatable {
    case idle
    case loading
    case results([Approval])
    case empty
    case error(String)
}

/// View model for the FLAT approvals surface. Sibling to
/// [[ApprovalsTreeViewModel]] which adds expansion state.
@MainActor
@Observable
public final class ApprovalsViewModel {
    public private(set) var state: ApprovalsState = .idle
    public private(set) var bundle: ApprovalsBundle = ApprovalsBundle(approvals: [], receipts: [])
    public var selected: Approval?
    public var searchText: String = ""
    public var statusFilter: ApprovalStatus?

    private let api: ApprovalsAPI
    private var fetchTask: Task<Void, Never>?

    public init(api: ApprovalsAPI) {
        self.api = api
    }

    public func refresh() async {
        fetchTask?.cancel()
        await runFetch()
    }

    public func select(_ approval: Approval) {
        selected = approval
    }

    public func clearSelection() {
        selected = nil
    }

    /// Receipts attached to an approval — pre-filtered to bundleable rows so
    /// the inspector doesn't show invoice-vs-receipt siblings that aren't
    /// eligible for Workday submission.
    public func receipts(for approval: Approval) -> [Receipt] {
        bundle.receipts
            .filter { $0.approvalId == approval.id && $0.documentKind.isBundleable }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
    }

    /// Compose the current `searchText` + `statusFilter` against the bundle's
    /// approvals. Empty search returns all rows; filter on status `nil` is a
    /// no-op.
    public func filter(
        searchText: String? = nil,
        status: ApprovalStatus?? = nil
    ) -> [Approval] {
        if let searchText { self.searchText = searchText }
        if let status { self.statusFilter = status }
        return apply(self.searchText, self.statusFilter, bundle.approvals)
    }

    /// Test-only seam used by snapshot tests to force a deterministic state
    /// without going through `MockApprovalsAPI`.
    public func injectForSnapshots(state: ApprovalsState, bundle: ApprovalsBundle?) {
        self.state = state
        if let bundle { self.bundle = bundle }
    }

    private func apply(
        _ search: String,
        _ status: ApprovalStatus?,
        _ rows: [Approval]
    ) -> [Approval] {
        let lowered = search.lowercased()
        return rows.filter { approval in
            if let status, approval.status != status { return false }
            if !lowered.isEmpty {
                let haystack = """
                \(approval.title)
                \(approval.approver)
                \(approval.vendor ?? "")
                \(approval.category)
                """.lowercased()
                if !haystack.contains(lowered) { return false }
            }
            return true
        }
    }

    private func runFetch() async {
        state = .loading
        do {
            let response = try await api.list(ifNoneMatch: nil)
            if Task.isCancelled { return }
            if let bundle = response.bundle {
                self.bundle = bundle
            }
            let visible = apply(searchText, statusFilter, bundle.approvals)
            state = visible.isEmpty ? .empty : .results(visible)
        } catch is CancellationError {
            return
        } catch {
            state = .error(String(describing: error))
        }
    }
}
