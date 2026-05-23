import Foundation
import Models

/// Short-lived token returned by `/link/token/create`. The raw `token`
/// string is what LinkKit consumes. Plaid expires these in ~30 min in
/// sandbox and ~4 h in production; we surface the absolute deadline so
/// the UI can re-fetch instead of inferring a TTL.
public struct PlaidLinkToken: Sendable, Hashable {
    public let token: String
    public let expiration: Date

    public init(token: String, expiration: Date) {
        self.token = token
        self.expiration = expiration
    }
}

/// A linked Plaid "item" (institution login). The raw `access_token` lives
/// in the synapse-v2 Keychain; the client holds only the opaque keychain
/// reference key so a compromised device never leaks the long-lived secret.
public struct PlaidItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let institutionId: String
    public let institutionName: String
    /// Keychain alias for the access token. Phase 2 server resolves this
    /// back to the real token before calling Plaid; the client never sees it.
    public let accessTokenRef: String

    public init(
        id: String,
        institutionId: String,
        institutionName: String,
        accessTokenRef: String
    ) {
        self.id = id
        self.institutionId = institutionId
        self.institutionName = institutionName
        self.accessTokenRef = accessTokenRef
    }
}

/// One page of the Plaid `/transactions/sync` cursor stream. The native
/// types are intentionally reused — `Transaction` is the only ledger row
/// shape in the app.
public struct PlaidSyncDelta: Sendable {
    public let added: [Transaction]
    public let modified: [Transaction]
    public let removedIds: [String]
    public let nextCursor: String
    public let hasMore: Bool

    public init(
        added: [Transaction],
        modified: [Transaction],
        removedIds: [String],
        nextCursor: String,
        hasMore: Bool
    ) {
        self.added = added
        self.modified = modified
        self.removedIds = removedIds
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

/// Plaid's three deployment environments. Each maps to a distinct base URL
/// the synapse-v2 backend forwards calls to. The client never talks to
/// `plaid.com` directly — the server-side exchange pattern keeps the
/// client_id/secret off-device.
public enum PlaidEnvironment: String, Sendable, CaseIterable {
    case sandbox
    case development
    case production

    /// Plaid's documented per-environment base URLs. Surfaced here so the
    /// `LivePlaidConnector` can assert it's pointed at the right one and
    /// so test assertions can pin the value without re-hardcoding.
    public var baseURL: URL {
        switch self {
        case .sandbox:     return Self.sandboxURL
        case .development: return Self.developmentURL
        case .production:  return Self.productionURL
        }
    }

    public static let sandboxURL = URL(string: "https://sandbox.plaid.com")!
    public static let developmentURL = URL(string: "https://development.plaid.com")!
    public static let productionURL = URL(string: "https://production.plaid.com")!
}

/// Aggregate result from `PlaidSync.sync(itemId:cursor:)`. Returned to the
/// caller so the UI can show a "synced N transactions" toast and so the
/// next foreground refresh can resume from `cursor`.
public struct PlaidSyncResult: Sendable, Equatable {
    public let addedCount: Int
    public let modifiedCount: Int
    public let removedCount: Int
    public let cursor: String

    public init(
        addedCount: Int,
        modifiedCount: Int,
        removedCount: Int,
        cursor: String
    ) {
        self.addedCount = addedCount
        self.modifiedCount = modifiedCount
        self.removedCount = removedCount
        self.cursor = cursor
    }
}
