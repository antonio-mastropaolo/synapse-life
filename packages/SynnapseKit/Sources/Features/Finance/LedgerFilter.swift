import Foundation
import Models

/// Pending / posted scope for the iOS Transactions segmented control.
/// Lives next to `LedgerFilter` so the same surface can compose status
/// filtering with the existing search/category filter. The reducer is a
/// pure function so a view-model or view can call it directly.
public enum LedgerStatusScope: Sendable, Hashable, CaseIterable {
    case all
    case pending
    case posted

    /// Filter `rows` by the chosen scope. `.all` is identity.
    public func apply(to rows: [Transaction]) -> [Transaction] {
        switch self {
        case .all: return rows
        case .pending: return rows.filter(\.pending)
        case .posted: return rows.filter { !$0.pending }
        }
    }
}

/// Groups a flat ledger by `accountName` (falling back to `accountId`,
/// then "Unknown"). Returned tuple list is stable: section keys come
/// back sorted lexicographically so two callers with the same input
/// always produce the same section order.
public func groupTransactionsByCard(_ rows: [Transaction])
-> [(card: String, rows: [Transaction])] {
    let grouped = Dictionary(grouping: rows) { row -> String in
        row.accountName ?? row.accountId ?? "Unknown"
    }
    return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
}

/// Composable filter over a `[Transaction]`. Each field narrows further;
/// an empty filter returns the input unchanged. The reducer is pure so the
/// view model can call it on every keystroke without locking.
public struct LedgerFilter: Sendable, Equatable {
    public var dateRange: ClosedRange<Date>?
    public var accountIds: Set<String>
    public var categories: Set<String>
    public var searchText: String

    public init(
        dateRange: ClosedRange<Date>? = nil,
        accountIds: Set<String> = [],
        categories: Set<String> = [],
        searchText: String = ""
    ) {
        self.dateRange = dateRange
        self.accountIds = accountIds
        self.categories = categories
        self.searchText = searchText
    }

    public var isEmpty: Bool {
        dateRange == nil && accountIds.isEmpty && categories.isEmpty && searchText.isEmpty
    }

    /// Apply this filter to a list of transactions. Stable order — keeps
    /// caller-provided ordering intact.
    public func apply(to rows: [Transaction]) -> [Transaction] {
        if isEmpty { return rows }
        let needle = searchText.lowercased()
        return rows.filter { row in
            if let range = dateRange, !range.contains(row.date) { return false }
            if !accountIds.isEmpty {
                guard let id = row.accountId, accountIds.contains(id) else { return false }
            }
            if !categories.isEmpty {
                guard case .knownCategory(let s) = row.category, categories.contains(s) else {
                    return false
                }
            }
            if !needle.isEmpty {
                let haystack = "\(row.name)\n\(row.merchantName ?? "")".lowercased()
                if !haystack.contains(needle) { return false }
            }
            return true
        }
    }
}
