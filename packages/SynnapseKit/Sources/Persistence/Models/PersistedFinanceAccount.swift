import Foundation
import SwiftData
import Models

/// SwiftData mirror of `FinanceAccount` (the Sendable DTO).
///
/// `kindRaw` stores the `AccountKind.rawValue` so SwiftData doesn't have to
/// know about the custom enum. The `.kind` computed property projects back.
/// Decimal money values are persisted natively to preserve exactness.
@Model
public final class PersistedFinanceAccount {

    @Attribute(.unique) public var id: String

    public var institutionId: String?
    public var institutionName: String?
    public var name: String
    public var officialName: String?
    public var mask: String?

    /// Raw `AccountKind.rawValue`. Reading goes through the `kind` computed
    /// property; unknown values fall through to `.other` so a future
    /// taxonomy addition does not break the client.
    public var kindRaw: String

    public var currency: String
    public var currentBalance: Decimal?
    public var availableBalance: Decimal?
    public var limitAmount: Decimal?
    public var balanceCapturedAt: Date?

    /// Wall-clock instant at which this row was last written from a server
    /// sync. Used by the staleness banner and by the cursor logic in
    /// `PlaidTransactionsSync` (Phase 2).
    public var lastSyncedAt: Date

    public init(
        id: String,
        institutionId: String?,
        institutionName: String?,
        name: String,
        officialName: String?,
        mask: String?,
        kindRaw: String,
        currency: String,
        currentBalance: Decimal?,
        availableBalance: Decimal?,
        limitAmount: Decimal?,
        balanceCapturedAt: Date?,
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.institutionId = institutionId
        self.institutionName = institutionName
        self.name = name
        self.officialName = officialName
        self.mask = mask
        self.kindRaw = kindRaw
        self.currency = currency
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.limitAmount = limitAmount
        self.balanceCapturedAt = balanceCapturedAt
        self.lastSyncedAt = lastSyncedAt
    }

    /// Projected enum view of `kindRaw`. Falls through to `.other` on an
    /// unrecognised raw string so a future server-side taxonomy addition
    /// never traps the client.
    public var kind: AccountKind {
        AccountKind(rawValue: kindRaw) ?? .other
    }
}
