import Foundation
import Observation
import Models

@MainActor
@Observable
public final class ForecastViewModel {
    public private(set) var forecast: Forecast?
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    public var horizonDays: Int = 30

    private let api: ForecastAPI
    private var inFlight: Task<Void, Never>?

    public init(api: ForecastAPI) {
        self.api = api
    }

    public func refresh(account: FinanceAccount, transactions: [Transaction]) {
        inFlight?.cancel()
        let api = self.api
        let horizon = self.horizonDays
        isLoading = true
        inFlight = Task { [weak self] in
            do {
                let result = try await api.forecast(
                    account: account,
                    transactions: transactions,
                    horizonDays: horizon
                )
                if Task.isCancelled { return }
                self?.forecast = result
                self?.isLoading = false
            } catch {
                if Task.isCancelled { return }
                self?.lastError = String(describing: error)
                self?.isLoading = false
            }
        }
    }

    public func injectForSnapshots(_ forecast: Forecast) {
        self.forecast = forecast
        self.isLoading = false
    }
}
