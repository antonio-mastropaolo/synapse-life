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
    /// When `false`, pending transactions are dropped from the output.
    /// Default is `true` so legacy callers see no behavior change.
    public var showPending: Bool

    public init(
        dateRange: ClosedRange<Date>? = nil,
        accountIds: Set<String> = [],
        categories: Set<String> = [],
        searchText: String = "",
        showPending: Bool = true
    ) {
        self.dateRange = dateRange
        self.accountIds = accountIds
        self.categories = categories
        self.searchText = searchText
        self.showPending = showPending
    }

    public var isEmpty: Bool {
        dateRange == nil
            && accountIds.isEmpty
            && categories.isEmpty
            && searchText.isEmpty
            && showPending
    }

    /// Apply this filter to a list of transactions. Stable order — keeps
    /// caller-provided ordering intact.
    public func apply(to rows: [Transaction]) -> [Transaction] {
        if isEmpty { return rows }
        let needle = searchText.lowercased()
        return rows.filter { row in
            if !showPending, row.pending { return false }
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

/// One section in the grouped ledger. The account carries the institution
/// name and mask used in the section header; the transactions are already
/// filtered and sorted newest-first.
public struct CardGroup: Sendable, Equatable, Identifiable {
    public let account: FinanceAccount
    public let transactions: [Transaction]

    public init(account: FinanceAccount, transactions: [Transaction]) {
        self.account = account
        self.transactions = transactions
    }

    public var id: String { account.id }
}

extension LedgerFilter {
    /// Group filtered transactions by their owning account. Sections appear
    /// in the order accounts are passed in (deterministic for the caller),
    /// transactions inside each section are newest-first, and any account
    /// whose section would be empty after filtering is omitted.
    ///
    /// Rows whose `accountId` does not resolve against the provided accounts
    /// are dropped — without an account we can't render a section header
    /// truthfully, and silently bucketing them under "Unknown" would hide a
    /// real data-shape problem from the user.
    public func groupByCard(
        rows: [Transaction],
        accounts: [FinanceAccount]
    ) -> [CardGroup] {
        let filtered = apply(to: rows)
        let byAccount: [String: [Transaction]] = Dictionary(
            grouping: filtered,
            by: { $0.accountId ?? "" }
        )
        return accounts.compactMap { account -> CardGroup? in
            guard let bucket = byAccount[account.id], !bucket.isEmpty else { return nil }
            let sorted = bucket.sorted { $0.date > $1.date }
            return CardGroup(account: account, transactions: sorted)
        }
    }
}

extension FinanceAccount {
    /// Section-header label: "Institution Name •• 4223".
    /// Falls back to the account's own `name` when the institution string
    /// is missing, and omits the mask suffix when the account has none.
    public var cardSectionTitle: String {
        let institution = institutionName?.trimmingCharacters(in: .whitespaces)
        let primary = (institution?.isEmpty == false) ? institution! : name
        if let mask, !mask.isEmpty {
            return "\(primary) •• \(mask)"
        }
        return primary
    }
}
