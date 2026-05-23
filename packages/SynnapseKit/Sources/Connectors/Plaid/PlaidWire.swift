import Foundation
import Models

/// Request + response shapes for the synapse-v2 Plaid proxy
/// (`/api/connectors/plaid/*`). The server holds the client_id + secret and
/// the long-lived access tokens; these envelopes only ever carry the
/// short-lived link token and opaque item references. Decoding reuses the
/// native `Models` wire rows (`ServerTransactionRow`, `ServerFinanceItem`) so
/// the Plaid path and the legacy `/api/finance/*` path project identically.

// MARK: - Request bodies

struct PlaidLinkTokenRequest: Encodable, Sendable {
    let userId: String
}

struct PlaidExchangeRequest: Encodable, Sendable {
    let publicToken: String
}

struct PlaidSyncRequest: Encodable, Sendable {
    let itemId: String
    let cursor: String?
}

struct PlaidItemRequest: Encodable, Sendable {
    let itemId: String
}

// MARK: - Response envelopes

/// `/link-token/create`. `expiration` arrives as either an ISO-8601 string
/// (Plaid's own shape) or unix seconds (if the proxy normalizes); both decode.
struct PlaidLinkTokenEnvelope: Decodable, Sendable {
    let linkToken: String
    let expiration: Date

    enum CodingKeys: String, CodingKey { case linkToken, expiration }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.linkToken = try c.decode(String.self, forKey: .linkToken)
        if let n = try? c.decode(Double.self, forKey: .expiration) {
            self.expiration = Date(timeIntervalSince1970: n)
        } else if let s = try? c.decode(String.self, forKey: .expiration),
                  let d = ISO8601DateFormatter().date(from: s) {
            self.expiration = d
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .expiration, in: c,
                debugDescription: "expiration is neither unix seconds nor ISO-8601"
            )
        }
    }
}

/// `/item/public-token/exchange`. `accessTokenRef` is the server-side Keychain
/// alias — never the raw access token.
struct PlaidItemEnvelope: Decodable, Sendable {
    let itemId: String
    let institutionId: String
    let institutionName: String
    let accessTokenRef: String
}

/// `/transactions/sync`. Mirrors Plaid's cursor-delta shape; `removed` is a
/// flat id array because the proxy collapses Plaid's `{transaction_id}` objects.
struct PlaidSyncEnvelope: Decodable, Sendable {
    let added: [ServerTransactionRow]
    let modified: [ServerTransactionRow]
    let removed: [String]
    let nextCursor: String
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case added, modified, removed, nextCursor, hasMore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.added = try c.decodeIfPresent([ServerTransactionRow].self, forKey: .added) ?? []
        self.modified = try c.decodeIfPresent([ServerTransactionRow].self, forKey: .modified) ?? []
        self.removed = try c.decodeIfPresent([String].self, forKey: .removed) ?? []
        self.nextCursor = try c.decode(String.self, forKey: .nextCursor)
        self.hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

/// `/investments/get`. Same holding shape the legacy finance route emits.
struct PlaidInvestmentsEnvelope: Decodable, Sendable {
    let holdings: [PlaidHoldingRow]
}

struct PlaidHoldingRow: Decodable, Sendable {
    let accountId: String
    let accountName: String
    let securityId: String
    let ticker: String?
    let name: String?
    let type: String?
    let quantity: Double?
    let price: Double?
    let value: Double?
    let costBasis: Double?
    let unrealizedPnl: Double?
    let unrealizedPnlPct: Double?
    let currency: String?
}

extension PlaidHoldingRow {
    func toPosition() -> InvestmentPosition {
        InvestmentPosition(
            securityId: securityId,
            accountId: accountId,
            accountName: accountName,
            ticker: ticker,
            name: name,
            kind: SecurityKind.fromServerType(type),
            quantity: decimal(from: quantity) ?? .zero,
            price: decimal(from: price) ?? .zero,
            value: decimal(from: value) ?? .zero,
            costBasis: decimal(from: costBasis),
            unrealizedPnL: decimal(from: unrealizedPnl),
            unrealizedPnLPct: decimal(from: unrealizedPnlPct),
            currency: (currency ?? "USD").uppercased()
        )
    }
}

/// `/item/remove`. The proxy answers with an empty object on success; all
/// fields are optional so `{}` decodes without error.
struct PlaidOKEnvelope: Decodable, Sendable {
    let ok: Bool?
}
