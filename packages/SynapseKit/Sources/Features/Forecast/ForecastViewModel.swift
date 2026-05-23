import Foundation
import Observation
import Models
import SynapseCharts

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

    // MARK: - Forecast v2 chart inputs
    //
    // Agent A's chart and KPI grid pull these directly off the
    // [[BalanceProjection]] derived fields. The historical series is
    // a deterministic 14-day backward walk anchored at the projection's
    // starting checking balance — synthetic by design because we don't
    // yet ship a real daily-balance history from the API. The walk is
    // seeded by the starting balance so it's stable across reruns;
    // surface agents B/C/E should never inject their own series.

    public var historicalSeries: [MoneyTimePoint] {
        guard let projection else { return [] }
        return Self.historicalWalk(
            anchor: projection.startingChecking,
            today: projection.today,
            days: 14
        )
    }

    public var projectionSeries: [MoneyTimePoint] {
        projection?.dailyBalanceSeries ?? []
    }

    public var creditEvents: [ScheduledFlow] {
        projection?.scheduledCredits ?? []
    }

    public var debitEvents: [ScheduledFlow] {
        projection?.scheduledDebits ?? []
    }

    /// Builds a deterministic 14-day trailing walk anchored at
    /// `anchor`. We construct a small sine-wave wobble so the line
    /// has visible shape rather than a flat artefact, but the
    /// magnitude is small (±2% of the anchor) so it reads as
    /// "this is roughly where you were" rather than as a real signal.
    /// Replace with real daily-balance history once the API exposes it.
    static func historicalWalk(anchor: Decimal, today: Date, days: Int) -> [MoneyTimePoint] {
        guard days > 0 else { return [] }
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: today)
        let anchorDouble = (anchor as NSDecimalNumber).doubleValue
        let amplitude = max(anchorDouble * 0.02, 1.0)
        var out: [MoneyTimePoint] = []
        out.reserveCapacity(days)
        // Walk from `days` ago up to (but not including) today; the
        // projection series starts at today so historical hands off
        // cleanly without painting the same point twice.
        for offset in stride(from: days, through: 1, by: -1) {
            let date = startOfToday.addingTimeInterval(Double(-offset) * 86_400)
            // Deterministic wobble: sin of the day index scaled to
            // [-amplitude, +amplitude].
            let wobble = sin(Double(offset) * 0.65) * amplitude
            let value = Decimal(anchorDouble + wobble)
            out.append(MoneyTimePoint(date: date, amount: value))
        }
        return out
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
