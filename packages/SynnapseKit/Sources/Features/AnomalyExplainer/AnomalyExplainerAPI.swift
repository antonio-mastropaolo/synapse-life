import Foundation
import Models
import Networking

/// Anomaly explainer surface. Returns the full explanation in one
/// shot today; future versions will stream tokens through the
/// `IntelligenceRouter` so the sheet paints like the Ask bar does.
public protocol AnomalyExplainerAPI: Sendable {
    func explain(
        transaction: Transaction,
        recentTransactions: [Transaction],
        accountNames: Set<String>
    ) async throws -> AnomalyExplanation
}

public struct LiveAnomalyExplainerAPI: AnomalyExplainerAPI {
    private let serverContractLive: Bool
    private let fallback: LocalStubAnomalyExplainerAPI

    public init(client: APIClient, serverContractLive: Bool = false) {
        self.serverContractLive = serverContractLive
        self.fallback = LocalStubAnomalyExplainerAPI()
    }

    public func explain(
        transaction: Transaction,
        recentTransactions: [Transaction],
        accountNames: Set<String>
    ) async throws -> AnomalyExplanation {
        return try await fallback.explain(
            transaction: transaction,
            recentTransactions: recentTransactions,
            accountNames: accountNames
        )
    }
}

public struct LocalStubAnomalyExplainerAPI: AnomalyExplainerAPI {
    public init() {}

    public func explain(
        transaction: Transaction,
        recentTransactions: [Transaction],
        accountNames: Set<String>
    ) async throws -> AnomalyExplanation {
        return AnomalyExplainerReducer.explain(
            transaction: transaction,
            recentTransactions: recentTransactions,
            accountNames: accountNames
        )
    }
}
