import Foundation
import Models
import Networking

/// Live Plaid connector. Every call routes through the synapse-v2 backend
/// (`/api/connectors/plaid/*`); the server holds the client_id + secret and
/// the long-lived access tokens, so the client only ever sees the short-lived
/// link token and opaque item references. The connector inherits the standard
/// `APIClient` bearer/refresh + retry policy — it adds no `URLSession` calls of
/// its own.
public actor LivePlaidConnector: PlaidConnector {

    private let client: APIClient
    private let environment: PlaidEnvironment
    private let encoder: JSONEncoder

    /// `client` is the standard Synapse `APIClient`. `environment` is the Plaid
    /// environment the *server* is pointed at; the client forwards it as a
    /// header so the proxy can assert the two agree, and records it so the UI
    /// can show "(sandbox)".
    public init(client: APIClient, environment: PlaidEnvironment) {
        self.client = client
        self.environment = environment
        self.encoder = JSONEncoder()
    }

    public func createLinkToken(userId: String) async throws -> PlaidLinkToken {
        let env: PlaidLinkTokenEnvelope = try await post(
            path: "api/connectors/plaid/link-token/create",
            body: PlaidLinkTokenRequest(userId: userId)
        )
        return PlaidLinkToken(token: env.linkToken, expiration: env.expiration)
    }

    public func exchangePublicToken(_ publicToken: String) async throws -> PlaidItem {
        let env: PlaidItemEnvelope = try await post(
            path: "api/connectors/plaid/item/public-token/exchange",
            body: PlaidExchangeRequest(publicToken: publicToken)
        )
        return PlaidItem(
            id: env.itemId,
            institutionId: env.institutionId,
            institutionName: env.institutionName,
            accessTokenRef: env.accessTokenRef
        )
    }

    public func syncTransactions(
        itemId: String,
        cursor: String?
    ) async throws -> PlaidSyncDelta {
        let env: PlaidSyncEnvelope = try await post(
            path: "api/connectors/plaid/transactions/sync",
            body: PlaidSyncRequest(itemId: itemId, cursor: cursor)
        )
        return PlaidSyncDelta(
            added: env.added.map(Transaction.fromServerRow),
            modified: env.modified.map(Transaction.fromServerRow),
            removedIds: env.removed,
            nextCursor: env.nextCursor,
            hasMore: env.hasMore
        )
    }

    public func fetchAccounts(itemId: String) async throws -> [FinanceAccount] {
        let env: FinanceAccountsResponse = try await post(
            path: "api/connectors/plaid/accounts/get",
            body: PlaidItemRequest(itemId: itemId)
        )
        return env.accounts
    }

    public func fetchInvestments(itemId: String) async throws -> [InvestmentPosition] {
        let env: PlaidInvestmentsEnvelope = try await post(
            path: "api/connectors/plaid/investments/get",
            body: PlaidItemRequest(itemId: itemId)
        )
        return env.holdings.map { $0.toPosition() }
    }

    public func removeItem(itemId: String) async throws {
        let _: PlaidOKEnvelope = try await post(
            path: "api/connectors/plaid/item/remove",
            body: PlaidItemRequest(itemId: itemId)
        )
    }

    public nonisolated var environmentForExternalUse: PlaidEnvironment { environment }

    /// POST `body` as JSON to `path` and decode the proxy envelope. Translates
    /// `APIError` into the connector's `PlaidConnectorError` vocabulary so
    /// callers never have to reason about two error types.
    private func post<Body: Encodable, R: Decodable & Sendable>(
        path: String,
        body: Body
    ) async throws -> R {
        let data: Data
        do {
            data = try encoder.encode(body)
        } catch {
            throw PlaidConnectorError.transport
        }
        let endpoint = Endpoint<R>(
            method: .post,
            path: path,
            headers: [
                "Content-Type": "application/json",
                "X-Plaid-Environment": environment.rawValue,
            ],
            body: data
        )
        do {
            return try await client.send(endpoint)
        } catch let apiError as APIError {
            throw Self.map(apiError)
        } catch {
            throw PlaidConnectorError.transport
        }
    }

    private static func map(_ error: APIError) -> PlaidConnectorError {
        switch error {
        case .server(let status): return .server(status: status)
        case .decoding: return .decoding
        case .badURL: return .invalidURL
        case .unauthorized, .transport, .cancelled: return .transport
        }
    }
}
