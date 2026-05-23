import Foundation
import Models
import Networking

/// Weekly digest surface. Live path defers to local stub until the
/// server route lands at `POST /api/ai/digest` (forward-compat).
public protocol DigestAPI: Sendable {
    func digest(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        firstName: String
    ) async throws -> Digest
}

public struct LiveDigestAPI: DigestAPI {
    private let serverContractLive: Bool
    private let fallback: LocalStubDigestAPI

    public init(client: APIClient, serverContractLive: Bool = false) {
        self.serverContractLive = serverContractLive
        self.fallback = LocalStubDigestAPI()
    }

    public func digest(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        firstName: String
    ) async throws -> Digest {
        // Server route not shipped yet — until it is, always fall
        // through to the local reducer. The same forward-compat
        // pattern is used by InsightsAPI / CategorizationAPI.
        return try await fallback.digest(
            accounts: accounts,
            transactions: transactions,
            firstName: firstName
        )
    }
}

public struct LocalStubDigestAPI: DigestAPI {
    private let clock: @Sendable () -> Date

    public init(clock: @Sendable @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    public func digest(
        accounts: [FinanceAccount],
        transactions: [Transaction],
        firstName: String
    ) async throws -> Digest {
        return DigestReducer.generate(
            accounts: accounts,
            transactions: transactions,
            firstName: firstName,
            today: clock()
        )
    }
}
