import Foundation
import Observation
import Models

@MainActor
@Observable
public final class ForecastViewModel {

    // MARK: - Existing stochastic forecast (FinancePersonalView's chart)

    public private(set) var forecast: Forecast?
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    public var horizonDays: Int = 30

    // MARK: - Backed claims for the Forecast surface
    //
    // The stat cards and the "may hit zero on Day Y" banner read off
    // a deterministic [[BalanceProjection]] computed against the same
    // demo transactions the rest of the AI++ wedge consumes. The
    // values here REPLACE the previously-hardcoded copy on the
    // Forecast surface: every number on the screen now derives from
    // the user's transaction history rather than a string literal.

    public private(set) var projection: BalanceProjection?

    /// Total dollar amount of bills hitting in the next 30 days.
    /// Source: `projection.totalDebits`. Drives the "NEXT 30 DAYS OF
    /// BILLS · $X.XX" card.
    public var nextThirtyDaysBillsTotal: Decimal {
        projection?.totalDebits ?? 0
    }

    /// Count of predicted charges in the horizon. Source:
    /// `projection.predictedChargesCount`. Drives the "PREDICTED
    /// CHARGES · N" card.
    public var predictedChargesCount: Int {
        projection?.predictedChargesCount ?? 0
    }

    /// "Checking may hit zero on May 18" banner copy. `nil` when the
    /// projection never crosses zero in the horizon, so the view can
    /// hide the banner.
    public var projectedZeroBanner: String? {
        guard let date = projection?.projectedZeroDate else { return nil }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "Checking may hit zero on \(df.string(from: date))"
    }

    /// Ordered list of predicted debit flows in the horizon. Source:
    /// `projection.scheduledDebits`. Drives the predicted-charges
    /// list below the banner.
    public var predictedChargesList: [ScheduledFlow] {
        projection?.scheduledDebits ?? []
    }

    private let api: ForecastAPI
    private var inFlight: Task<Void, Never>?

    public init(api: ForecastAPI) {
        self.api = api
    }

    /// Convenience overload mirroring the old call-site shape used by
    /// `AppModel.refreshIntelligenceSurfaces()`. Computes BOTH the
    /// stochastic envelope (existing) and the deterministic
    /// projection (new) from the same transactions feed.
    public func refresh(account: FinanceAccount, transactions: [Transaction]) {
        refresh(
            accounts: [account],
            transactions: transactions
        )
    }

    /// Full-fledged refresh. The deterministic projection sums across
    /// every checking-style account; the stochastic chart still pins
    /// to a single account (the first checking-like one) because its
    /// drift model is per-account.
    public func refresh(accounts: [FinanceAccount], transactions: [Transaction]) {
        inFlight?.cancel()
        let api = self.api
        let horizon = self.horizonDays
        let primary = accounts.first(where: { $0.kind == .checking }) ?? accounts.first
        isLoading = true

        // Deterministic projection runs immediately (pure logic) so
        // the Forecast view's claims render synchronously.
        let recurrings = RecurringDetector.detectRecurrings(transactions: transactions)
        let income = RecurringDetector.detectIncomeRecurrings(transactions: transactions)
        self.projection = BalanceProjector.project(
            accounts: accounts,
            recurrings: recurrings,
            incomeRecurrings: income,
            horizonDays: horizon
        )

        // The stochastic chart still defers to the API stub so we
        // get the band envelope shape FinancePersonalView's chart
        // already consumes.
        guard let primary else {
            isLoading = false
            return
        }
        inFlight = Task { [weak self] in
            do {
                let result = try await api.forecast(
                    account: primary,
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

    /// Inject a pre-computed projection for previews / snapshot tests
    /// so the Forecast surface paints deterministic content without
    /// needing the full transaction-history seed.
    public func injectProjectionForSnapshots(_ projection: BalanceProjection) {
        self.projection = projection
    }
}
