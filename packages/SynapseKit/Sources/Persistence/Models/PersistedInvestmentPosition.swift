import Foundation
import SwiftData
import Models

/// SwiftData mirror of `InvestmentPosition` (the Sendable DTO).
///
/// The DTO's natural key is `(accountId, securityId)`; we synthesise the
/// composite as the row's id so SwiftData's `.unique` attribute can enforce
/// it and so the projection layer can round-trip identity.
///
/// Money / quantity values are persisted as canonical decimal Strings (`*Raw`)
/// rather than native SwiftData `Decimal`, which routes through `Double` and
/// drops precision past ~15 significant figures — a real hazard here because
/// share quantities and unit prices carry more than cents of precision. The
/// String round-trip via `Decimal.description` / `Decimal(string:)` is exact.
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

    /// Canonical decimal String backings; see the type doc for why.
    public var quantityRaw: String
    public var priceRaw: String
    public var valueRaw: String
    public var costBasisRaw: String?
    public var unrealizedPnLRaw: String?
    public var unrealizedPnLPctRaw: String?

    public var quantity: Decimal {
        get { Decimal(string: quantityRaw) ?? .zero }
        set { quantityRaw = newValue.description }
    }

    public var price: Decimal {
        get { Decimal(string: priceRaw) ?? .zero }
        set { priceRaw = newValue.description }
    }

    public var value: Decimal {
        get { Decimal(string: valueRaw) ?? .zero }
        set { valueRaw = newValue.description }
    }

    public var costBasis: Decimal? {
        get { costBasisRaw.flatMap { Decimal(string: $0) } }
        set { costBasisRaw = newValue.map { $0.description } }
    }

    public var unrealizedPnL: Decimal? {
        get { unrealizedPnLRaw.flatMap { Decimal(string: $0) } }
        set { unrealizedPnLRaw = newValue.map { $0.description } }
    }

    public var unrealizedPnLPct: Decimal? {
        get { unrealizedPnLPctRaw.flatMap { Decimal(string: $0) } }
        set { unrealizedPnLPctRaw = newValue.map { $0.description } }
    }

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
        self.quantityRaw = quantity.description
        self.priceRaw = price.description
        self.valueRaw = value.description
        self.costBasisRaw = costBasis.map { $0.description }
        self.unrealizedPnLRaw = unrealizedPnL.map { $0.description }
        self.unrealizedPnLPctRaw = unrealizedPnLPct.map { $0.description }
        self.currency = currency
        self.lastSyncedAt = lastSyncedAt
    }

    public var kind: SecurityKind {
        SecurityKind(rawValue: kindRaw) ?? .other
    }
}
