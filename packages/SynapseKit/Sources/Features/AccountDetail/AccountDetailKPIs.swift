import Foundation
import Models

/// The KPI cluster rendered above the recent-transactions list. All
/// values are Decimal so we never round through Double. `monthIncome`
/// is optional because liability accounts (credit, loan) don't see
/// inflows in the usual sense — the UI hides that card on those
/// accounts rather than painting a misleading "$0".
public struct AccountDetailKPISet: Sendable, Equatable, Hashable {
    public let monthSpend: Decimal
    public let monthIncome: Decimal?
    public let avgDailySpend: Decimal
    public let daysSinceCapture: Int?

    public init(
        monthSpend: Decimal,
        monthIncome: Decimal?,
        avgDailySpend: Decimal,
        daysSinceCapture: Int?
    ) {
        self.monthSpend = monthSpend
        self.monthIncome = monthIncome
        self.avgDailySpend = avgDailySpend
        self.daysSinceCapture = daysSinceCapture
    }
}

/// Pure KPI math for [[AccountDetailViewModel]]. All four helpers are
/// stateless and read from the same `[Transaction]` slice the VM
/// holds. Tests pin each one independently so a regression in one
/// helper doesn't masquerade as a broken VM.
public enum AccountDetailKPIs {

    /// Sum of debits (signed-negative transactions) whose date falls
    /// in the same calendar month as `today`. Returns a positive
    /// magnitude — the UI is going to prefix a `-` itself.
    public static func monthSpend(
        from transactions: [Transaction],
        today: Date
    ) -> Decimal {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: today)
        var total: Decimal = 0
        for tx in transactions {
            guard let amount = tx.amount, !tx.pending, amount < 0 else { continue }
            let txComps = cal.dateComponents([.year, .month], from: tx.date)
            if txComps.year == comps.year && txComps.month == comps.month {
                total += absDecimal(amount)
            }
        }
        return total
    }

    /// Sum of credits (signed-positive transactions) for the current
    /// calendar month. Returns `nil` on accounts whose `kind` is a
    /// liability — the credit-card panel shouldn't claim there's
    /// "income" of $0 just because nobody refunded a charge.
    public static func monthIncome(
        from transactions: [Transaction],
        today: Date,
        accountKind: AccountKind
    ) -> Decimal? {
        if accountKind.isLiability { return nil }
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: today)
        var total: Decimal = 0
        for tx in transactions {
            guard let amount = tx.amount, !tx.pending, amount > 0 else { continue }
            let txComps = cal.dateComponents([.year, .month], from: tx.date)
            if txComps.year == comps.year && txComps.month == comps.month {
                total += amount
            }
        }
        return total
    }

    /// Average daily spend over the trailing `windowDays`. Computed
    /// as `total_debits / windowDays` so quiet days drag the figure
    /// down — that's the honest reading. Returns zero when the window
    /// has no debits.
    public static func avgDailySpend(
        from transactions: [Transaction],
        today: Date,
        windowDays: Int = 30
    ) -> Decimal {
        guard windowDays > 0 else { return 0 }
        let earliest = today.addingTimeInterval(-Double(windowDays) * 86_400)
        var total: Decimal = 0
        for tx in transactions {
            guard let amount = tx.amount, !tx.pending, amount < 0 else { continue }
            guard tx.date >= earliest, tx.date <= today else { continue }
            total += absDecimal(amount)
        }
        return total / Decimal(windowDays)
    }

    /// Days since the server last refreshed the balance for this
    /// account. `nil` when the account never captured a balance (the
    /// wire model allows it). The figure feeds the inspector pane's
    /// "Captured X days ago" label so the operator can tell stale
    /// data from fresh.
    public static func daysSinceCapture(
        _ account: FinanceAccount,
        today: Date
    ) -> Int? {
        guard let captured = account.balanceCapturedAt else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let startToday = cal.startOfDay(for: today)
        let startCaptured = cal.startOfDay(for: captured)
        let comps = cal.dateComponents([.day], from: startCaptured, to: startToday)
        return max(0, comps.day ?? 0)
    }
}
