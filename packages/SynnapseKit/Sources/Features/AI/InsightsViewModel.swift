import Foundation
import Observation
import Models

/// Drives one strip of AI insight cards next to data. Read-only — the
/// pane calls `refresh(accounts:transactions:)` and the VM exposes the
/// cards. Sensitivity comes from settings preferences and is bound
/// externally.
@MainActor
@Observable
public final class InsightsViewModel {
    public private(set) var insights: [Insight] = []
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    public var sensitivity: Int = 3

    private let api: InsightsAPI
    private var inFlight: Task<Void, Never>?

    public init(api: InsightsAPI) {
        self.api = api
    }

    public func refresh(accounts: [FinanceAccount], transactions: [Transaction]) {
        inFlight?.cancel()
        isLoading = true
        let api = self.api
        inFlight = Task { [weak self] in
            do {
                let result = try await api.insights(accounts: accounts, transactions: transactions)
                if Task.isCancelled { return }
                self?.insights = result
                self?.isLoading = false
            } catch {
                if Task.isCancelled { return }
                self?.lastError = String(describing: error)
                self?.isLoading = false
            }
        }
    }

    /// Snapshot seam — bypass the API and paint a fixed deck of cards.
    public func injectForSnapshots(_ cards: [Insight]) {
        self.insights = cards
        self.isLoading = false
    }
}
