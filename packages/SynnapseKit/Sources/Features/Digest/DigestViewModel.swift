import Foundation
import Observation
import Models

/// Drives the weekly digest card surface. Cached daily — the host can
/// call `refresh(...)` on appear and the VM only re-runs the reducer
/// when the active week has changed.
@MainActor
@Observable
public final class DigestViewModel {
    public private(set) var digest: Digest?
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    public var firstName: String = "Antonio"

    private let api: DigestAPI
    private let clock: @MainActor () -> Date
    private var inFlight: Task<Void, Never>?

    public init(api: DigestAPI, clock: @MainActor @escaping () -> Date = { Date() }) {
        self.api = api
        self.clock = clock
    }

    public func refresh(accounts: [FinanceAccount], transactions: [Transaction]) {
        inFlight?.cancel()
        let api = self.api
        let firstName = self.firstName
        isLoading = true
        inFlight = Task { [weak self] in
            do {
                let result = try await api.digest(
                    accounts: accounts,
                    transactions: transactions,
                    firstName: firstName
                )
                if Task.isCancelled { return }
                self?.digest = result
                self?.isLoading = false
            } catch {
                if Task.isCancelled { return }
                self?.lastError = String(describing: error)
                self?.isLoading = false
            }
        }
    }

    /// Snapshot seam — bypass the API and paint a fixed digest.
    public func injectForSnapshots(_ digest: Digest) {
        self.digest = digest
        self.isLoading = false
    }
}
