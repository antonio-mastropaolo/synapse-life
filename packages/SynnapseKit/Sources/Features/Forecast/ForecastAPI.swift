import Foundation
import Models
import Networking

/// Cash-flow forecast surface. Live path defers to local stub until
/// the server route lands at `POST /api/ai/forecast` (forward-compat).
public protocol ForecastAPI: Sendable {
    func forecast(
        account: FinanceAccount,
        transactions: [Transaction],
        horizonDays: Int
    ) async throws -> Forecast
}

public struct LiveForecastAPI: ForecastAPI {
    private let serverContractLive: Bool
    private let fallback: LocalStubForecastAPI

    public init(client: APIClient, serverContractLive: Bool = false) {
        self.serverContractLive = serverContractLive
        self.fallback = LocalStubForecastAPI()
    }

    public func forecast(
        account: FinanceAccount,
        transactions: [Transaction],
        horizonDays: Int
    ) async throws -> Forecast {
        return try await fallback.forecast(
            account: account,
            transactions: transactions,
            horizonDays: horizonDays
        )
    }
}

public struct LocalStubForecastAPI: ForecastAPI {
    private let clock: @Sendable () -> Date

    public init(clock: @Sendable @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    public func forecast(
        account: FinanceAccount,
        transactions: [Transaction],
        horizonDays: Int
    ) async throws -> Forecast {
        let predicted = ForecastReducer.predictedRecurrings(transactions: transactions, today: clock())
        return ForecastReducer.project(
            account: account,
            transactions: transactions,
            predictedCharges: predicted,
            today: clock(),
            horizonDays: horizonDays
        )
    }
}
