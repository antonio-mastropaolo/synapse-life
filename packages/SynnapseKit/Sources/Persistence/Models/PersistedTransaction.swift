import Foundation
import SwiftData
import Models

/// SwiftData mirror of `Transaction` (the Sendable DTO).
///
/// `categoryRaw` is the server's category string verbatim (or `nil` when
/// unknown). The `category` computed property projects it back into a
/// `TransactionCategory` for the UI. Decimal `amount` is persisted natively;
/// the sign convention matches the wire format (negative = outflow).
@Model
public final class PersistedTransaction {

    @Attribute(.unique) public var id: String

    public var accountId: String?
    public var accountName: String?

    /// Signed amount: negative = debit (outflow), positive = credit (inflow).
    public var amount: Decimal?

    public var currency: String

    /// Transaction date (canonical day for posted, or pending pseudo-date).
    public var date: Date

    public var name: String
    public var merchantName: String?

    /// The server's raw category string; `nil` when uncategorised.
    /// Projected through `.category` to the typed enum.
    public var categoryRaw: String?
    public var subcategory: String?

    public var pending: Bool

    /// Wall-clock instant at which this row was last written from a server
    /// sync. Used by Phase 2's `/transactions/sync` cursor delta logic.
    public var lastSyncedAt: Date

    public init(
        id: String,
        accountId: String?,
        accountName: String?,
        amount: Decimal?,
        currency: String,
        date: Date,
        name: String,
        merchantName: String?,
        categoryRaw: String?,
        subcategory: String?,
        pending: Bool,
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.amount = amount
        self.currency = currency
        self.date = date
        self.name = name
        self.merchantName = merchantName
        self.categoryRaw = categoryRaw
        self.subcategory = subcategory
        self.pending = pending
        self.lastSyncedAt = lastSyncedAt
    }

    public var category: TransactionCategory {
        if let raw = categoryRaw, !raw.isEmpty {
            return .knownCategory(raw)
        }
        return .unknown
    }
}
