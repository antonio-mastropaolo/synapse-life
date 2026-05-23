import Foundation
import Models
import Networking

/// Live Plaid connector that will, in Phase 2, route every call through the
/// synapse-v2 backend (`/api/connectors/plaid/*`). The server holds the
/// client_id + secret; the client only ever sees the link token and item
/// references. Today this is a scaffold: each method asserts the URL it
/// would call and then throws `.notImplemented` so the seam is provably
/// wired without pulling in the real SDK.
public actor LivePlaidConnector: PlaidConnector {

    private let client: APIClient
    private let environment: PlaidEnvironment

    /// `client` is the standard Synapse `APIClient` — every call inherits
    /// the bearer/refresh path and the retry policy. `environment` is the
    /// Plaid environment the *server* is pointed at; the client just
    /// records it so the UI can show "(sandbox)" and so tests can assert.
    public init(client: APIClient, environment: PlaidEnvironment) {
        self.client = client
        self.environment = environment
    }

    /// Phase 2 will fill these in. For now we construct the endpoint so
    /// the path is exercised (and a typo surfaces in tests) before
    /// throwing.
    public func createLinkToken(userId: String) async throws -> PlaidLinkToken {
        _ = try await assertEndpoint(path: "api/connectors/plaid/link-token/create")
        throw PlaidConnectorError.notImplemented
    }

    public func exchangePublicToken(_ publicToken: String) async throws -> PlaidItem {
        _ = try await assertEndpoint(path: "api/connectors/plaid/item/public-token/exchange")
        throw PlaidConnectorError.notImplemented
    }

    public func syncTransactions(
        itemId: String,
        cursor: String?
    ) async throws -> PlaidSyncDelta {
        _ = try await assertEndpoint(path: "api/connectors/plaid/transactions/sync")
        throw PlaidConnectorError.notImplemented
    }

    public func fetchAccounts(itemId: String) async throws -> [FinanceAccount] {
        _ = try await assertEndpoint(path: "api/connectors/plaid/accounts/get")
        throw PlaidConnectorError.notImplemented
    }

    public func fetchInvestments(itemId: String) async throws -> [InvestmentPosition] {
        _ = try await assertEndpoint(path: "api/connectors/plaid/investments/get")
        throw PlaidConnectorError.notImplemented
    }

    public func removeItem(itemId: String) async throws {
        _ = try await assertEndpoint(path: "api/connectors/plaid/item/remove")
        throw PlaidConnectorError.notImplemented
    }

    /// Constructs (but does not send) the endpoint that the Phase 2
    /// implementation will use. Surfaces a `.invalidURL` if the relative
    /// path can't be composed against the client's base URL — Phase 2
    /// will replace the throw at the call site with a real `client.send`.
    @discardableResult
    private func assertEndpoint(path: String) async throws -> URL {
        let base = await client.baseURLForExternalUse
        let endpoint = Endpoint<PlaidEmptyResponse>(method: .post, path: path)
        do {
            return try endpoint.url(relativeTo: base)
        } catch {
            throw PlaidConnectorError.invalidURL
        }
    }

    /// Exposed for tests so they can prove the seam reaches the right
    /// path without firing the network.
    public func resolveEndpointURL(path: String) async throws -> URL {
        try await assertEndpoint(path: path)
    }

    public nonisolated var environmentForExternalUse: PlaidEnvironment { environment }
}

/// Placeholder decode target — never actually decoded today because every
/// `LivePlaidConnector` method throws before `client.send` runs. Phase 2
/// replaces this with the per-endpoint response types.
struct PlaidEmptyResponse: Decodable, Sendable {}
