import Foundation
import Observation
import Models

/// Drives the "Why?" sheet on an anomaly card. The host pushes the
/// triggering transaction + the recent context window; the VM
/// requests the explanation and exposes loading state for the sheet.
@MainActor
@Observable
public final class AnomalyExplainerViewModel {
    public private(set) var explanation: AnomalyExplanation?
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    private let api: AnomalyExplainerAPI
    private var inFlight: Task<Void, Never>?

    public init(api: AnomalyExplainerAPI) {
        self.api = api
    }

    public func request(
        transaction: Transaction,
        recentTransactions: [Transaction],
        accountNames: Set<String>
    ) {
        inFlight?.cancel()
        let api = self.api
        isLoading = true
        explanation = nil
        inFlight = Task { [weak self] in
            do {
                let result = try await api.explain(
                    transaction: transaction,
                    recentTransactions: recentTransactions,
                    accountNames: accountNames
                )
                if Task.isCancelled { return }
                self?.explanation = result
                self?.isLoading = false
            } catch {
                if Task.isCancelled { return }
                self?.lastError = String(describing: error)
                self?.isLoading = false
            }
        }
    }

    public func injectForSnapshots(_ explanation: AnomalyExplanation) {
        self.explanation = explanation
        self.isLoading = false
    }
}
