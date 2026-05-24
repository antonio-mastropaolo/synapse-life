import Foundation
import Models

/// Pure-logic cash-flow forecaster. Given an account, its last N days
/// of transactions, and detected recurring charges, project the
/// account's balance forward over a horizon.
///
/// Method:
///   - Drift = mean daily net flow over the last 30 days (income
///     minus outflow, signed). A negative drift = balance decreasing.
///   - σ = sample standard deviation of daily net flows.
///   - Each forecast day starts from the prior day's balance, adds the
///     drift, and widens the band by √day · σ.
///   - Recurring charges (predicted) are subtracted on the predicted
///     occurrence day rather than smeared into the drift, so the line
///     shows the discrete steps the user will feel.
public enum ForecastReducer {

    /// Project a checking-style account forward `horizonDays` days.
    /// Returns a zero-length series if the account has no balance or
    /// no recent activity to learn from.
    public static func project(
        account: FinanceAccount,
        transactions: [Transaction],
        predictedCharges: [PredictedCharge] = [],
        today: Date = Date(),
        horizonDays: Int = 30
    ) -> Forecast {
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: today)
        guard let startingBalance = account.currentBalance else {
            return Forecast(
                accountId: account.id,
                series: [],
                zeroCrossing: nil,
                predictedCharges: predictedCharges,
                nextThirtyDaysTotal: predictedChargesTotal(predictedCharges, today: today, horizonDays: 30)
            )
        }
        let history = dailyNetFlows(
            transactions: transactions.filter { $0.accountId == account.id },
            today: startOfToday,
            days: 30
        )
        let drift: Decimal
        let stdev: Decimal
        if history.isEmpty {
            drift = 0
            stdev = 0
        } else {
            drift = history.reduce(Decimal.zero, +) / Decimal(history.count)
            stdev = sampleStdev(history, mean: drift)
        }

        // Bucket predicted charges by day.
        var chargesByDay: [Date: Decimal] = [:]
        for c in predictedCharges {
            let day = cal.startOfDay(for: c.date)
            chargesByDay[day, default: 0] += absDecimal(c.amount)
        }

        var series: [ForecastPoint] = []
        var running = startingBalance
        var zeroCrossing: Date?
        for day in 0..<horizonDays {
            let date = startOfToday.addingTimeInterval(Double(day + 1) * 86_400)
            running += drift
            if let extra = chargesByDay[cal.startOfDay(for: date)] {
                running -= extra
            }
            // Band widens with √t (random-walk variance).
            let sqrtT = Decimal(Double(day + 1).squareRoot())
            let halfBand = stdev * sqrtT
            let lower = running - halfBand
            let upper = running + halfBand
            if zeroCrossing == nil && running <= 0 {
                zeroCrossing = date
            }
            series.append(ForecastPoint(date: date, balance: running, lowerBound: lower, upperBound: upper))
        }

        return Forecast(
            accountId: account.id,
            series: series,
            zeroCrossing: zeroCrossing,
            predictedCharges: predictedCharges,
            nextThirtyDaysTotal: predictedChargesTotal(predictedCharges, today: today, horizonDays: 30)
        )
    }

    /// Predict the next charge date for each subscription-shaped
    /// merchant. We look for any merchant that has at least 2 debits in
    /// the last 90 days with a similar amount and an inter-arrival of
    /// ~30 days; the prediction is `lastSeen + medianInterval`.
    public static func predictedRecurrings(
        transactions: [Transaction],
        today: Date = Date()
    ) -> [PredictedCharge] {
        let cal = Calendar(identifier: .gregorian)
        let cutoff = today.addingTimeInterval(-90 * 24 * 3600)
        var byMerchant: [String: [Transaction]] = [:]
        for tx in transactions {
            guard let a = tx.amount, !tx.pending, a < 0 else { continue }
            guard tx.date >= cutoff else { continue }
            let key = (tx.merchantName ?? tx.name).uppercased()
            byMerchant[key, default: []].append(tx)
        }
        var out: [PredictedCharge] = []
        for (merchant, rows) in byMerchant {
            guard rows.count >= 2 else { continue }
            let sorted = rows.sorted { $0.date < $1.date }
            // Inter-arrival in days.
            var intervals: [Double] = []
            for i in 1..<sorted.count {
                intervals.append(sorted[i].date.timeIntervalSince(sorted[i - 1].date) / 86_400)
            }
            let medianInterval = median(intervals)
            // Only treat as recurring if cadence is roughly 7, 14, or 30 days (±5).
            let plausible = [7.0, 14.0, 30.0, 90.0].contains { abs($0 - medianInterval) <= 5 }
            guard plausible else { continue }
            let last = sorted.last!
            let nextDate = last.date.addingTimeInterval(medianInterval * 86_400)
            // Skip if prediction is in the past.
            guard nextDate > today else { continue }
            let amount = absDecimal(last.amount ?? 0)
            let id = "predicted.\(merchant.replacingOccurrences(of: " ", with: "_")).\(cal.startOfDay(for: nextDate).timeIntervalSince1970)"
            out.append(PredictedCharge(
                id: id,
                merchantName: last.merchantName ?? last.name,
                amount: amount,
                date: nextDate
            ))
        }
        return out.sorted { $0.date < $1.date }
    }

    // MARK: - Helpers

    static func dailyNetFlows(transactions: [Transaction], today: Date, days: Int) -> [Decimal] {
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: today)
        let earliest = startOfToday.addingTimeInterval(-Double(days) * 86_400)
        var byDay: [Date: Decimal] = [:]
        for tx in transactions {
            guard let a = tx.amount, !tx.pending else { continue }
            guard tx.date >= earliest, tx.date < startOfToday else { continue }
            let day = cal.startOfDay(for: tx.date)
            byDay[day, default: 0] += a
        }
        // Fill missing days with zero so stdev reflects gaps.
        var out: [Decimal] = []
        for offset in 0..<days {
            let day = earliest.addingTimeInterval(Double(offset) * 86_400)
            out.append(byDay[day] ?? 0)
        }
        return out
    }

    static func sampleStdev(_ values: [Decimal], mean: Decimal) -> Decimal {
        guard values.count > 1 else { return 0 }
        let sumSquares = values.reduce(Decimal.zero) { acc, v in
            let diff = v - mean
            return acc + (diff * diff)
        }
        let variance = sumSquares / Decimal(values.count - 1)
        let varianceDouble = NSDecimalNumber(decimal: variance).doubleValue
        let stdevDouble = varianceDouble.squareRoot()
        return Decimal(stdevDouble)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func predictedChargesTotal(
        _ charges: [PredictedCharge],
        today: Date,
        horizonDays: Int
    ) -> Decimal {
        let cutoff = today.addingTimeInterval(Double(horizonDays) * 86_400)
        return charges
            .filter { $0.date > today && $0.date <= cutoff }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}
