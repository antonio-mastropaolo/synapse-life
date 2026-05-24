import Foundation
import Models
import Networking

/// Client-side AI insights surface. Two implementations:
///   - `LiveInsightsAPI` calls `POST /api/ai/insights` on synapse-v2
///     (route not shipped yet — falls back to the local stub when
///     `serverContractLive == false`).
///   - `LocalStubInsightsAPI` runs `InsightsReducer` directly so the UI
///     always has something useful to render.
public protocol InsightsAPI: Sendable {
    func insights(
        accounts: [FinanceAccount],
        transactions: [Transaction]
    ) async throws -> [Insight]
}

/// Default live implementation. Forward-compat against
/// `POST /api/ai/insights` — until the server ships the route the
/// `serverContractLive` flag stays `false` and every call falls through
/// to the local reducer.
public struct LiveInsightsAPI: InsightsAPI {
    private let baseURL: URL
    private let session: URLSession
    private let serverContractLive: Bool
    private let fallback: LocalStubInsightsAPI

    public init(client: APIClient, serverContractLive: Bool = false) {
        self.baseURL = client.baseURLForExternalUse
        self.session = client.sessionForExternalUse
        self.serverContractLive = serverContractLive
        self.fallback = LocalStubInsightsAPI()
    }

    public func insights(
        accounts: [FinanceAccount],
        transactions: [Transaction]
    ) async throws -> [Insight] {
        guard serverContractLive else {
            return try await fallback.insights(accounts: accounts, transactions: transactions)
        }
        let url = baseURL.appendingPathComponent("api/ai/insights")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = InsightsRequestBody(
            accounts: accounts.map(InsightsRequestBody.AccountSnapshot.init(from:)),
            transactions: transactions.map(InsightsRequestBody.TransactionSnapshot.init(from:))
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return try await fallback.insights(accounts: accounts, transactions: transactions)
        }
        do {
            let envelope = try JSONDecoder().decode(InsightsResponseBody.self, from: data)
            return envelope.insights
        } catch {
            return try await fallback.insights(accounts: accounts, transactions: transactions)
        }
    }
}

/// Local-only reducer-backed implementation. The view models default to
/// this until `LiveInsightsAPI(serverContractLive: true)` is wired.
public struct LocalStubInsightsAPI: InsightsAPI {
    private let sensitivity: Int
    private let maxCount: Int
    private let clock: @Sendable () -> Date

    public init(
        sensitivity: Int = 3,
        maxCount: Int = 3,
        clock: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.sensitivity = sensitivity
        self.maxCount = maxCount
        self.clock = clock
    }

    public func insights(
        accounts: [FinanceAccount],
        transactions: [Transaction]
    ) async throws -> [Insight] {
        return InsightsReducer.reduce(
            accounts: accounts,
            transactions: transactions,
            today: clock(),
            sensitivity: sensitivity,
            maxCount: maxCount
        )
    }
}

// MARK: - Wire shape

struct InsightsRequestBody: Encodable, Sendable {
    let accounts: [AccountSnapshot]
    let transactions: [TransactionSnapshot]

    struct AccountSnapshot: Encodable, Sendable {
        let id: String
        let kind: String
        let currentBalance: String?
        let currency: String

        init(from account: FinanceAccount) {
            self.id = account.id
            self.kind = account.kind.rawValue
            self.currentBalance = account.currentBalance.map { "\($0)" }
            self.currency = account.currency
        }
    }

    struct TransactionSnapshot: Encodable, Sendable {
        let id: String
        let accountId: String?
        let amount: String?
        let date: Double
        let name: String
        let category: String
        let pending: Bool

        init(from tx: Transaction) {
            self.id = tx.id
            self.accountId = tx.accountId
            self.amount = tx.amount.map { "\($0)" }
            self.date = tx.date.timeIntervalSince1970
            self.name = tx.name
            self.category = tx.category.displayLabel
            self.pending = tx.pending
        }
    }
}

struct InsightsResponseBody: Decodable, Sendable {
    let insights: [Insight]
}
