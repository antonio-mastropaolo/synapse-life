import Foundation

/// Native account row, projected from the Synapse v2 `/api/finance/accounts`
/// response. Plaid's `type` + `subtype` pair is collapsed into a single
/// `AccountKind` so the UI doesn't have to know about the Plaid taxonomy.
public struct FinanceAccount: Sendable, Hashable, Identifiable {
    public let id: String
    public let institutionId: String?
    public let institutionName: String?
    public let name: String
    public let officialName: String?
    public let mask: String?
    public let kind: AccountKind
    public let currency: String
    public let currentBalance: Decimal?
    public let availableBalance: Decimal?
    public let limitAmount: Decimal?
    public let balanceCapturedAt: Date?

    public init(
        id: String,
        institutionId: String?,
        institutionName: String?,
        name: String,
        officialName: String?,
        mask: String?,
        kind: AccountKind,
        currency: String,
        currentBalance: Decimal?,
        availableBalance: Decimal?,
        limitAmount: Decimal?,
        balanceCapturedAt: Date?
    ) {
        self.id = id
        self.institutionId = institutionId
        self.institutionName = institutionName
        self.name = name
        self.officialName = officialName
        self.mask = mask
        self.kind = kind
        self.currency = currency
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.limitAmount = limitAmount
        self.balanceCapturedAt = balanceCapturedAt
    }
}

/// Native taxonomy. Forward-compatible: any Plaid (type, subtype) pair that
/// the table below doesn't know about falls through to `.other` so a server
/// addition never breaks the client. Liabilities (`credit`, `loan`) are
/// classified separately because `PortfolioReducer` flips their sign in
/// net-worth math.
public enum AccountKind: String, Codable, Sendable, Hashable, CaseIterable {
    case checking
    case savings
    case credit
    case brokerage
    case retirement
    case loan
    case other

    /// Net-worth math: liabilities subtract from assets.
    public var isLiability: Bool {
        switch self {
        case .credit, .loan: return true
        default: return false
        }
    }

    /// Collapse Plaid's two-dimensional taxonomy to a flat enum.
    public static func fromPlaid(type: String?, subtype: String?) -> AccountKind {
        let t = (type ?? "").lowercased()
        let s = (subtype ?? "").lowercased()
        switch t {
        case "depository":
            if s.contains("savings") { return .savings }
            return .checking
        case "credit":
            return .credit
        case "loan":
            return .loan
        case "investment":
            // Retirement accounts (IRA / 401k / Roth) live under
            // `investment` in Plaid; we surface them as `.retirement` so the
            // UI can use a different tile color and the reducer can
            // optionally exclude them from "spendable" calculations.
            if s.contains("ira") || s.contains("401") || s.contains("roth")
                || s.contains("retire") || s.contains("pension") {
                return .retirement
            }
            return .brokerage
        default:
            return .other
        }
    }
}

// MARK: - Wire shape

/// Wire row mirroring `app/api/finance/accounts/route.ts` — one account
/// inside the `items[].accounts[]` array. Names match the JSON keys.
public struct ServerFinanceAccountRow: Decodable, Sendable {
    public let id: String
    public let name: String
    public let officialName: String?
    public let mask: String?
    public let type: String
    public let subtype: String?
    public let currency: String
    public let balance: ServerFinanceBalance
}

public struct ServerFinanceBalance: Decodable, Sendable {
    public let current: Double?
    public let available: Double?
    public let limit: Double?
    public let capturedAt: Double?
}

/// One Plaid item / link with its accounts nested underneath.
public struct ServerFinanceItem: Decodable, Sendable {
    public let id: String
    public let provider: String?
    public let institutionId: String?
    public let institutionName: String?
    public let itemStatus: String?
    public let lastSyncAt: Double?
    public let lastSyncError: String?
    public let accounts: [ServerFinanceAccountRow]
}

public struct ServerFinanceAccountsResponse: Decodable, Sendable {
    public let items: [ServerFinanceItem]
}

/// Decoded list of accounts already projected into native rows. This is
/// what the repository exposes to view models.
public struct FinanceAccountsResponse: Decodable, Sendable {
    public let accounts: [FinanceAccount]

    public init(accounts: [FinanceAccount]) {
        self.accounts = accounts
    }

    public init(from decoder: Decoder) throws {
        let envelope = try ServerFinanceAccountsResponse(from: decoder)
        var flattened: [FinanceAccount] = []
        for item in envelope.items {
            for row in item.accounts {
                flattened.append(FinanceAccount.fromServerRow(row, item: item))
            }
        }
        self.accounts = flattened
    }
}

extension FinanceAccount {
    /// Project a server row + its parent item into the native shape. We
    /// preserve Decimal money values through a string round-trip so doubles
    /// like 12345.67 don't acquire 1e-14 ghosts.
    public static func fromServerRow(
        _ row: ServerFinanceAccountRow,
        item: ServerFinanceItem
    ) -> FinanceAccount {
        let kind = AccountKind.fromPlaid(type: row.type, subtype: row.subtype)
        let captured = row.balance.capturedAt.map { Date(timeIntervalSince1970: $0 / 1000.0) }
        return FinanceAccount(
            id: row.id,
            institutionId: item.institutionId,
            institutionName: item.institutionName,
            name: row.name,
            officialName: row.officialName,
            mask: row.mask,
            kind: kind,
            currency: row.currency.uppercased(),
            currentBalance: decimal(from: row.balance.current),
            availableBalance: decimal(from: row.balance.available),
            limitAmount: decimal(from: row.balance.limit),
            balanceCapturedAt: captured
        )
    }
}

/// Bridge a JSON-decoded Double into a Decimal without introducing the
/// classic floating-point ghosts on round numbers. Goes through a string so
/// `12345.67` decodes as exactly `12345.67`.
@inlinable
public func decimal(from double: Double?) -> Decimal? {
    guard let double else { return nil }
    return Decimal(string: String(double))
}
