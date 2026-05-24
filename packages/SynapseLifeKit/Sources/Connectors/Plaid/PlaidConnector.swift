import Foundation
import Models

/// Phase-2 seam: the abstract surface every Plaid client (stub + live)
/// implements. The rest of the app — `PlaidSync`, `AccountStore` writers,
/// the LinkKit shim — codes against this protocol so the real-SDK swap is a
/// one-line dependency change.
///
/// All methods are `async throws` and every return type is `Sendable` so the
/// protocol composes cleanly with Swift 6 strict concurrency.
public protocol PlaidConnector: Sendable {

    /// Server-side `/link/token/create`. The client_id + secret never leave
    /// the synapse-v2 backend; the iOS app hands the returned short-lived
    /// token to LinkKit.
    func createLinkToken(userId: String) async throws -> PlaidLinkToken

    /// Trade a one-shot `public_token` from LinkKit for a long-lived
    /// `access_token`. The raw access token is stored in Keychain on the
    /// server side; the client only gets back a reference key.
    func exchangePublicToken(_ publicToken: String) async throws -> PlaidItem

    /// Cursor-paginated transactions delta. Mirrors Plaid's
    /// `/transactions/sync` semantics: pass `nil` cursor for the first
    /// call, then the previous response's `nextCursor` until `hasMore`
    /// goes false.
    func syncTransactions(
        itemId: String,
        cursor: String?
    ) async throws -> PlaidSyncDelta

    /// Snapshot of accounts under an item. Returns the same native
    /// `FinanceAccount` shape the rest of the app already projects — we do
    /// NOT introduce a parallel Plaid taxonomy.
    func fetchAccounts(itemId: String) async throws -> [FinanceAccount]

    /// Snapshot of investment holdings under an item.
    func fetchInvestments(itemId: String) async throws -> [InvestmentPosition]

    /// Detach an item server-side. After this returns the access token
    /// reference is invalid and Plaid won't bill us for it anymore.
    func removeItem(itemId: String) async throws
}

/// Errors the connector surface can throw. The `notImplemented` case is the
/// scaffold signal — `LivePlaidConnector` throws it everywhere until Phase 2
/// fills the real SDK + secret in.
public enum PlaidConnectorError: Error, Sendable, Equatable {
    case notImplemented
    case invalidURL
    case transport
    case server(status: Int)
    case decoding
    case missingCursor
}
