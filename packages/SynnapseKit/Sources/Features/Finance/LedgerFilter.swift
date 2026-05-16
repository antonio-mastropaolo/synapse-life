import Foundation
import Models

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
