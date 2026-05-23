import Foundation

/// One brokerage / retirement position. Projected from
/// `/api/finance/investments/route.ts` `holdings` array. Money values are
/// Decimal — never Double — so price-times-quantity math is exact.
public struct InvestmentPosition: Sendable, Hashable, Identifiable {
    /// (account, security) is the natural key from Plaid. We synthesize a
    /// composite id so SwiftUI's `ForEach` has a stable identity even when
    /// the same security appears in multiple accounts.
    public var id: String { "\(accountId):\(securityId)" }

    public let securityId: String
    public let accountId: String
    public let accountName: String
    public let ticker: String?
    public let name: String?
    public let kind: SecurityKind
    public let quantity: Decimal
    public let price: Decimal
    public let value: Decimal
    public let costBasis: Decimal?
    public let unrealizedPnL: Decimal?
    public let unrealizedPnLPct: Decimal?
    public let currency: String

    public init(
        securityId: String,
        accountId: String,
        accountName: String,
        ticker: String?,
        name: String?,
        kind: SecurityKind,
        quantity: Decimal,
        price: Decimal,
        value: Decimal,
        costBasis: Decimal?,
        unrealizedPnL: Decimal?,
        unrealizedPnLPct: Decimal?,
        currency: String
    ) {
        self.securityId = securityId
        self.accountId = accountId
        self.accountName = accountName
        self.ticker = ticker
        self.name = name
        self.kind = kind
        self.quantity = quantity
        self.price = price
        self.value = value
        self.costBasis = costBasis
        self.unrealizedPnL = unrealizedPnL
        self.unrealizedPnLPct = unrealizedPnLPct
        self.currency = currency
    }
}

public enum SecurityKind: String, Codable, Sendable, Hashable, CaseIterable {
    case stock
    case etf
    case bond
    case cash
    case other

    public static func fromServerType(_ t: String?) -> SecurityKind {
        guard let t = t?.lowercased() else { return .other }
        if t.contains("etf") { return .etf }
        if t.contains("cash") || t.contains("money") { return .cash }
        if t.contains("bond") || t.contains("fixed") { return .bond }
        if t.contains("equity") || t == "stock" { return .stock }
        if t.contains("mutual") { return .etf }
        return .other
    }
}
