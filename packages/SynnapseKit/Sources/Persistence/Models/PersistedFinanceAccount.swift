import Foundation
import SwiftData
import Models

/// SwiftData mirror of `FinanceAccount` (the Sendable DTO).
///
/// `kindRaw` stores the `AccountKind.rawValue` so SwiftData doesn't have to
/// know about the custom enum. The `.kind` computed property projects back.
/// Money values are persisted as canonical decimal Strings (`*Raw`) rather
/// than native SwiftData `Decimal`, which routes through `Double` and drops
/// precision past ~15 significant figures. The String round-trip via
/// `Decimal.description` / `Decimal(string:)` is base-10 and exact.
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

    /// Canonical decimal String backings; see the type doc for why.
    public var currentBalanceRaw: String?
    public var availableBalanceRaw: String?
    public var limitAmountRaw: String?

    public var currentBalance: Decimal? {
        get { currentBalanceRaw.flatMap { Decimal(string: $0) } }
        set { currentBalanceRaw = newValue.map { $0.description } }
    }

    public var availableBalance: Decimal? {
        get { availableBalanceRaw.flatMap { Decimal(string: $0) } }
        set { availableBalanceRaw = newValue.map { $0.description } }
    }

    public var limitAmount: Decimal? {
        get { limitAmountRaw.flatMap { Decimal(string: $0) } }
        set { limitAmountRaw = newValue.map { $0.description } }
    }

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
        self.currentBalanceRaw = currentBalance.map { $0.description }
        self.availableBalanceRaw = availableBalance.map { $0.description }
        self.limitAmountRaw = limitAmount.map { $0.description }
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
