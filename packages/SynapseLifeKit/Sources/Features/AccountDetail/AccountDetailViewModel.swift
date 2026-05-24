import Foundation
import Observation
import Models

/// View model for the per-account drill-down. Pure projection — given
/// the account + the global transactions slice at init, every output
/// is deterministic and synchronous. No async, no API.
///
/// The shell constructs one of these per `.accountDetail(id:)` route.
/// Switching to a different account creates a fresh instance via the
/// detail pane's `Group { switch ... }` — that's by design, because
/// the per-account state (selected range, sync error) is scoped to
/// one account.
@MainActor
@Observable
public final class AccountDetailViewModel {

    /// The resolved account this VM renders. Held by value because
    /// `FinanceAccount` is a value type — switching accounts in the
    /// shell rebuilds the VM, it does not mutate this slot.
    public let account: FinanceAccount

    /// All transactions known to the shell (typically the flattened
    /// rows from `FinanceTransactionsViewModel`). The VM filters this
    /// down to the account-scoped slice in `scopedTransactions` —
    /// keeping the input loose means the shell doesn't have to do the
    /// filtering, and it survives transactions arriving after VM init.
    public private(set) var allTransactions: [Transaction]

    /// Recurring detections that hit THIS account. Computed once at
    /// init off the account-scoped slice so the detector only sees
    /// charges actually billed here.
    public private(set) var recurrings: [DetectedRecurring]

    /// Selected range for the balance chart. The view binds chips to
    /// this; changing it recomputes `balanceSeries` lazily.
    public var range: AccountDetailBalanceSeries.Range

    /// Optional sync-error string. The wire model exposes
    /// `lastSyncError` on the parent `ServerFinanceItem`, but the
    /// projection layer strips it today. This slot is the integration
    /// seam: when the live repository starts plumbing the error, the
    /// shell sets this from outside and the banner paints. Stays
    /// `nil` in the demo path.
    public var syncError: String?

    /// The "now" anchor for KPI math + balance walk. Defaults to
    /// `Date()` for production; tests pin a deterministic value.
    public let today: Date

    public init(
        account: FinanceAccount,
        allTransactions: [Transaction],
        range: AccountDetailBalanceSeries.Range = .d90,
        today: Date = Date(),
        syncError: String? = nil
    ) {
        self.account = account
        self.allTransactions = allTransactions
        self.range = range
        self.today = today
        self.syncError = syncError
        // Detect recurrings up-front against the account-scoped slice.
        // The detector only sees this account's debits, so subscription
        // detections won't bleed across accounts (e.g. Anthropic
        // charged to the credit card won't show up on the checking
        // detail view).
        let scoped = allTransactions.filter { $0.accountId == account.id }
        self.recurrings = RecurringDetector.detectRecurrings(
            transactions: scoped,
            today: today
        )
    }

    /// Account-scoped transactions, newest first, capped at 50 rows
    /// for the recent-activity table. 50 is the same cap the existing
    /// iOS inspector uses — kept consistent so the two surfaces feel
    /// the same.
    public var scopedTransactions: [Transaction] {
        allTransactions
            .filter { $0.accountId == account.id }
            .sorted { $0.date > $1.date }
            .prefix(50)
            .map { $0 }
    }

    /// All account-scoped transactions (uncapped), used internally by
    /// the balance walk + KPI helpers. Public so the view can render
    /// "Showing 50 of N" if it wants.
    public var allScopedTransactions: [Transaction] {
        allTransactions.filter { $0.accountId == account.id }
    }

    /// Balance series for the current `range`. Walked deterministically
    /// from the account's `currentBalance` anchor backward through the
    /// scoped transactions. Returns at least 2 points so the chart
    /// always has a line.
    public var balanceSeries: [BalancePoint] {
        let anchor = account.currentBalance ?? 0
        return AccountDetailBalanceSeries.walk(
            anchor: anchor,
            transactions: allScopedTransactions,
            range: range,
            today: today
        )
    }

    /// The four KPI numbers rendered above the recent-activity list.
    public var kpis: AccountDetailKPISet {
        AccountDetailKPISet(
            monthSpend: AccountDetailKPIs.monthSpend(
                from: allScopedTransactions, today: today
            ),
            monthIncome: AccountDetailKPIs.monthIncome(
                from: allScopedTransactions,
                today: today,
                accountKind: account.kind
            ),
            avgDailySpend: AccountDetailKPIs.avgDailySpend(
                from: allScopedTransactions, today: today
            ),
            daysSinceCapture: AccountDetailKPIs.daysSinceCapture(
                account, today: today
            )
        )
    }

    /// Test/preview hook. Replaces the held transactions and
    /// recomputes recurrings against the new slice.
    public func injectForSnapshots(allTransactions: [Transaction]) {
        self.allTransactions = allTransactions
        let scoped = allTransactions.filter { $0.accountId == account.id }
        self.recurrings = RecurringDetector.detectRecurrings(
            transactions: scoped,
            today: today
        )
    }
}
