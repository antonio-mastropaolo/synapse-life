import Foundation
import SwiftData
import Models

/// SwiftData mirror of `InvestmentPosition` (the Sendable DTO).
///
/// The DTO's natural key is `(accountId, securityId)`; we synthesise the
/// composite as the row's id so SwiftData's `.unique` attribute can enforce
/// it and so the projection layer can round-trip identity.
@Model
public final class PersistedInvestmentPosition {

    @Attribute(.unique) public var id: String  // "\(accountId):\(securityId)"

    public var securityId: String
    public var accountId: String
    public var accountName: String

    public var ticker: String?
    public var positionName: String?

    /// Raw `SecurityKind.rawValue`. Projected through `.kind`; unknown
    /// values fall through to `.other`.
    public var kindRaw: String

    public var quantity: Decimal
    public var price: Decimal
    public var value: Decimal
    public var costBasis: Decimal?
    public var unrealizedPnL: Decimal?
    public var unrealizedPnLPct: Decimal?

    public var currency: String

    public var lastSyncedAt: Date

    public init(
        securityId: String,
        accountId: String,
        accountName: String,
        ticker: String?,
        positionName: String?,
        kindRaw: String,
        quantity: Decimal,
        price: Decimal,
        value: Decimal,
        costBasis: Decimal?,
        unrealizedPnL: Decimal?,
        unrealizedPnLPct: Decimal?,
        currency: String,
        lastSyncedAt: Date = Date()
    ) {
        self.id = "\(accountId):\(securityId)"
        self.securityId = securityId
        self.accountId = accountId
        self.accountName = accountName
        self.ticker = ticker
        self.positionName = positionName
        self.kindRaw = kindRaw
        self.quantity = quantity
        self.price = price
        self.value = value
        self.costBasis = costBasis
        self.unrealizedPnL = unrealizedPnL
        self.unrealizedPnLPct = unrealizedPnLPct
        self.currency = currency
        self.lastSyncedAt = lastSyncedAt
    }

    public var kind: SecurityKind {
        SecurityKind(rawValue: kindRaw) ?? .other
    }
}
