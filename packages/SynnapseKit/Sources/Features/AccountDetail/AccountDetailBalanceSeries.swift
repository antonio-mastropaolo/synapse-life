import Foundation
import Models

/// One point on the balance-over-time chart. Decimal so we never lose
/// cents through the projection. Forward-ordered (`date` ascending) is
/// the canonical shape — that's what `Charts.LineMark` wants.
public struct BalancePoint: Sendable, Equatable, Hashable, Identifiable {
    public let date: Date
    public let balance: Decimal

    public var id: Date { date }

    public init(date: Date, balance: Decimal) {
        self.date = date
        self.balance = balance
    }
}

/// Synthetic balance walker. The server has no balance-history
/// endpoint today — the brief explicitly allows "if real data isn't
/// available, paint a deterministic walk anchored at current balance."
/// This walker takes the current `anchor` (today's balance) plus the
/// account-scoped transactions, then reconstructs backward:
///
/// - We walk **backward** from today day by day.
/// - On each day with transactions, the running balance steps by
///   `-sum(signed amounts)` — because today's balance already reflects
///   those flows, so the *previous* day's balance was today minus
///   them.
/// - Days without transactions hold the previous balance (flat
///   segment).
/// - We then reverse the array so the output is forward-ordered for
///   the chart.
///
/// Deterministic, account-scoped, uses real transaction signal. Quiet
/// accounts paint a flat line (correct). Ranges that extend past the
/// transaction tail hold flat — no fabricated noise.
public enum AccountDetailBalanceSeries {

    /// Time horizon for the chart. Aligned with `Range` on
    /// [[AccountDetailViewModel]] so the view layer can pass through.
    public enum Range: Sendable, Equatable, Hashable, CaseIterable {
        case d7, d30, d90, d1y, all

        /// Window length in days. `.all` returns 730 (two years) as a
        /// sane upper bound — the per-account transactions slice will
        /// have run out long before then for any real fixture.
        public var days: Int {
            switch self {
            case .d7:  return 7
            case .d30: return 30
            case .d90: return 90
            case .d1y: return 365
            case .all: return 730
            }
        }

        public var label: String {
            switch self {
            case .d7:  return "7D"
            case .d30: return "30D"
            case .d90: return "90D"
            case .d1y: return "1Y"
            case .all: return "All"
            }
        }
    }

    /// Walk a deterministic balance series back from `anchor` through
    /// the given transactions, scoped to the chosen `range`.
    ///
    /// `transactions` should already be filtered to a single account.
    /// Empty input → flat line at `anchor` across the range.
    public static func walk(
        anchor: Decimal,
        transactions: [Transaction],
        range: Range,
        today: Date
    ) -> [BalancePoint] {
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: today)
        let days = range.days

        // Sum transactions by start-of-day UTC. Negative amounts =
        // outflow, positive = inflow. We use Decimal end-to-end.
        var netByDay: [Date: Decimal] = [:]
        for tx in transactions {
            guard let amount = tx.amount, !tx.pending else { continue }
            let day = cal.startOfDay(for: tx.date)
            netByDay[day, default: 0] += amount
        }

        // Walk backward. `runningBalance` starts at today's anchor and
        // represents the balance at the START of each day we're
        // visiting. For a transaction-bearing day, the previous day's
        // balance was `running - net` (we strip that day's flow from
        // today's number). Days with no transactions hold flat.
        var points: [BalancePoint] = []
        var running: Decimal = anchor
        for offset in 0...days {
            let day = cal.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            points.append(BalancePoint(date: day, balance: running))
            if let net = netByDay[day] {
                running -= net
            }
        }

        // Output forward-ordered (chart expects ascending date).
        return points.reversed()
    }
}
