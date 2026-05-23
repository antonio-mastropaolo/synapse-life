import Foundation
import Models
import Networking

/// Result of a finance accounts fetch. ETag + 304 forward-compat mirrors
/// the spotlight + approvals shape. Synapse v2's
/// `/api/finance/accounts` does not yet emit `ETag` — when it does, the
/// repository will pick it up for free.
public struct FinanceAccountsAPIResponse: Sendable, Equatable {
    public let accounts: [FinanceAccount]?
    public let etag: String?
    public let notModified: Bool

    public init(accounts: [FinanceAccount]?, etag: String?, notModified: Bool) {
        self.accounts = accounts
        self.etag = etag
        self.notModified = notModified
    }
}

public struct FinanceTransactionsAPIResponse: Sendable, Equatable {
    public let rows: [Transaction]
    public let nextCursor: String?

    public init(rows: [Transaction], nextCursor: String?) {
        self.rows = rows
        self.nextCursor = nextCursor
    }
}

public protocol FinanceAPI: Sendable {
    func accounts(ifNoneMatch: String?) async throws -> FinanceAccountsAPIResponse
    func transactions(
        accountId: String?,
        cursor: String?
    ) async throws -> FinanceTransactionsAPIResponse
    func investments() async throws -> [InvestmentPosition]
}

/// Live implementation reading from `/api/finance/*`. Drops below the
/// typed `APIClient.send` path because the accounts route's 304 semantics
/// need raw header access.
///
/// Server-contract gaps as of M5:
///   - `/api/finance/accounts` does not emit `ETag` or accept
///     `If-None-Match`. Native client requests both and tolerates the
///     server returning a plain 200 every time.
///   - `/api/finance/transactions` does not emit `nextCursor` today; the
///     route paginates by `?days=` + `?limit=`. Native client honors
///     `nextCursor` when present (forward-compat) and stops otherwise.
///   - `/api/finance/investments` shape is already aligned.
public struct LiveFinanceAPI: FinanceAPI {
    private let baseURL: URL
    private let session: URLSession

    public init(client: APIClient) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
    }

    public func accounts(ifNoneMatch: String?) async throws -> FinanceAccountsAPIResponse {
        let url = baseURL.appendingPathComponent("api/finance/accounts")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        let etag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag")
        if http.statusCode == 304 {
            return FinanceAccountsAPIResponse(accounts: nil, etag: etag, notModified: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder.synapseFinance.decode(
                FinanceAccountsResponse.self, from: data
            )
            return FinanceAccountsAPIResponse(
                accounts: envelope.accounts, etag: etag, notModified: false
            )
        } catch {
            throw APIError.decoding
        }
    }

    public func transactions(
        accountId: String?,
        cursor: String?
    ) async throws -> FinanceTransactionsAPIResponse {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/finance/transactions"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = []
        if let accountId {
            queryItems.append(URLQueryItem(name: "accountId", value: accountId))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if !queryItems.isEmpty { comps?.queryItems = queryItems }
        guard let url = comps?.url else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder.synapseFinance.decode(
                TransactionsResponse.self, from: data
            )
            return FinanceTransactionsAPIResponse(
                rows: envelope.rows, nextCursor: envelope.nextCursor
            )
        } catch {
            throw APIError.decoding
        }
    }

    public func investments() async throws -> [InvestmentPosition] {
        let url = baseURL.appendingPathComponent("api/finance/investments")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            let envelope = try JSONDecoder.synapseFinance.decode(
                ServerInvestmentsResponse.self, from: data
            )
            return envelope.holdings.map { row in
                InvestmentPosition(
                    securityId: row.securityId,
                    accountId: row.accountId,
                    accountName: row.accountName,
                    ticker: row.ticker,
                    name: row.name,
                    kind: SecurityKind.fromServerType(row.type),
                    quantity: decimal(from: row.quantity) ?? .zero,
                    price: decimal(from: row.price) ?? .zero,
                    value: decimal(from: row.value) ?? .zero,
                    costBasis: decimal(from: row.costBasis),
                    unrealizedPnL: decimal(from: row.unrealizedPnl),
                    unrealizedPnLPct: decimal(from: row.unrealizedPnlPct),
                    currency: (row.currency ?? "USD").uppercased()
                )
            }
        } catch {
            throw APIError.decoding
        }
    }
}

// Wire shape for the investments endpoint. Lives in the API file because
// it's never consumed by anything else.
private struct ServerInvestmentsResponse: Decodable, Sendable {
    let holdings: [ServerHoldingRow]
}

private struct ServerHoldingRow: Decodable, Sendable {
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

/// Test/preview double. Mirrors the shape of [[MockSpotlightAPI]] so the
/// view models exercise the same actor-isolated handshake.
public actor MockFinanceAPI: FinanceAPI {
    private var nextAccounts: [FinanceAccount] = []
    private var nextEtag: String?
    private var nextNotModified: Bool = false
    private var nextTransactions: [Transaction] = []
    private var nextCursor: String?
    private var nextInvestments: [InvestmentPosition] = []
    private var nextError: Error?
    public private(set) var accountsCallCount: Int = 0
    public private(set) var transactionsCallCount: Int = 0
    public private(set) var lastTransactionsAccountId: String?

    public init() {}

    public func setAccounts(_ accounts: [FinanceAccount], etag: String? = nil) {
        nextAccounts = accounts
        nextEtag = etag
        nextNotModified = false
        nextError = nil
    }

    public func setAccountsNotModified(etag: String?) {
        nextNotModified = true
        nextEtag = etag
        nextError = nil
    }

    public func setTransactions(_ transactions: [Transaction], nextCursor: String? = nil) {
        nextTransactions = transactions
        self.nextCursor = nextCursor
        nextError = nil
    }

    public func setInvestments(_ positions: [InvestmentPosition]) {
        nextInvestments = positions
        nextError = nil
    }

    public func setNextError(_ error: Error) {
        nextError = error
    }

    public func accounts(ifNoneMatch: String?) async throws -> FinanceAccountsAPIResponse {
        accountsCallCount += 1
        if let err = nextError { throw err }
        if nextNotModified {
            return FinanceAccountsAPIResponse(accounts: nil, etag: nextEtag, notModified: true)
        }
        return FinanceAccountsAPIResponse(
            accounts: nextAccounts, etag: nextEtag, notModified: false
        )
    }

    public func transactions(
        accountId: String?,
        cursor: String?
    ) async throws -> FinanceTransactionsAPIResponse {
        transactionsCallCount += 1
        lastTransactionsAccountId = accountId
        if let err = nextError { throw err }
        return FinanceTransactionsAPIResponse(
            rows: nextTransactions, nextCursor: nextCursor
        )
    }

    public func investments() async throws -> [InvestmentPosition] {
        if let err = nextError { throw err }
        return nextInvestments
    }
}
