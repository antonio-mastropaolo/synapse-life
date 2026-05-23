import Foundation
import Models

/// Phase 4 — the proactive insights engine. A pure, deterministic function
/// over an `AlertsSnapshot` that a nightly `BGTaskScheduler` pass (or a
/// foreground refresh) runs against the persisted store to surface things the
/// user hasn't asked about: bills due soon, brand-new subscriptions, and
/// category spend that's spiking against its own history.
///
/// It composes the engines that already exist — `ForecastReducer`'s recurring
/// prediction for the bill / new-recurring signals — and adds a fresh weekly
/// z-score detector for the anomaly signal. Stateless: the caller dedups
/// across runs using the stable `ProactiveSignal.id`.
public enum ProactiveAnalyzer {

    public struct Configuration: Sendable {
        /// A known recurring whose predicted charge lands within this many
        /// days of `now` surfaces as an upcoming bill.
        public var lookaheadDays: Int
        /// Minimum z-score for a current-week category total to count as an
        /// anomaly. 2.0 ≈ the top ~2.5% of a normal tail.
        public var anomalyZThreshold: Double
        /// z at or above this escalates the anomaly from `.warning` to
        /// `.alert`.
        public var anomalyAlertZ: Double
        /// How many trailing weeks of history feed the baseline.
        public var historyWeeks: Int
        /// A category needs at least this many weeks with spend before its
        /// baseline is trustworthy enough to flag against.
        public var minimumActiveWeeks: Int

        public init(
            lookaheadDays: Int = 7,
            anomalyZThreshold: Double = 2.0,
            anomalyAlertZ: Double = 3.0,
            historyWeeks: Int = 8,
            minimumActiveWeeks: Int = 4
        ) {
            self.lookaheadDays = lookaheadDays
            self.anomalyZThreshold = anomalyZThreshold
            self.anomalyAlertZ = anomalyAlertZ
            self.historyWeeks = historyWeeks
            self.minimumActiveWeeks = minimumActiveWeeks
        }
    }

    public static func analyze(
        snapshot: AlertsSnapshot,
        configuration: Configuration = Configuration()
    ) -> [ProactiveSignal] {
        var signals: [ProactiveSignal] = []
        signals.append(contentsOf: recurringSignals(snapshot: snapshot, configuration: configuration))
        signals.append(contentsOf: anomalySignals(snapshot: snapshot, configuration: configuration))
        return ranked(signals)
    }

    // MARK: - Recurring (upcoming bill + new recurring)

    /// A predicted recurring is a NEW recurring when its merchant isn't in
    /// `priorMerchants` (more salient, so it wins); otherwise, if it's due
    /// within the lookahead, it's an upcoming bill. A merchant never produces
    /// both in one pass.
    static func recurringSignals(
        snapshot: AlertsSnapshot,
        configuration: Configuration
    ) -> [ProactiveSignal] {
        let predicted = ForecastReducer.predictedRecurrings(
            transactions: snapshot.transactions,
            today: snapshot.now
        )
        let lookaheadCutoff = snapshot.now.addingTimeInterval(Double(configuration.lookaheadDays) * 86_400)

        return predicted.compactMap { charge -> ProactiveSignal? in
            let merchantKey = charge.merchantName.uppercased()
            let isKnown = snapshot.priorMerchants.contains(merchantKey)

            if !isKnown {
                let slug = merchantKey.replacingOccurrences(of: " ", with: "_")
                return ProactiveSignal(
                    id: "proactive.newRecurring.\(slug)",
                    kind: .newRecurring,
                    headline: "New recurring: \(charge.merchantName)",
                    body: "Looks like a new \(formatCurrency(charge.amount)) recurring charge — next around \(formatShortDate(charge.date)).",
                    subjectId: charge.id,
                    date: charge.date,
                    severity: .info
                )
            }

            guard charge.date <= lookaheadCutoff else { return nil }
            return ProactiveSignal(
                id: "proactive.upcomingBill.\(charge.id)",
                kind: .upcomingBill,
                headline: "Upcoming bill: \(charge.merchantName)",
                body: "Predicted \(formatCurrency(charge.amount)) charge around \(formatShortDate(charge.date)).",
                subjectId: charge.id,
                date: charge.date,
                severity: .info
            )
        }
    }

    // MARK: - Anomalous spend (weekly z-score)

    static func anomalySignals(
        snapshot: AlertsSnapshot,
        configuration: Configuration
    ) -> [ProactiveSignal] {
        let cal = Calendar(identifier: .gregorian)
        let currentWeekStart = snapshot.now.addingTimeInterval(-7 * 86_400)

        // Per category: weekly debit totals keyed by bucket index (0 = current
        // week, 1..historyWeeks = trailing baseline), plus the largest
        // current-week debit id for the jump target.
        struct CategoryWeeks {
            var buckets: [Int: Double] = [:]
            var currentLargest: (id: String, amount: Double)?
        }
        var byCategory: [String: CategoryWeeks] = [:]

        for tx in snapshot.transactions {
            guard let amount = tx.amount, amount < 0, !tx.pending else { continue }
            guard tx.date <= snapshot.now else { continue }
            let weeksAgo = Int(snapshot.now.timeIntervalSince(tx.date) / (7 * 86_400))
            guard weeksAgo >= 0, weeksAgo <= configuration.historyWeeks else { continue }
            let magnitude = NSDecimalNumber(decimal: absDecimal(amount)).doubleValue
            let key = tx.category.displayLabel

            var entry = byCategory[key] ?? CategoryWeeks()
            entry.buckets[weeksAgo, default: 0] += magnitude
            if weeksAgo == 0 {
                if entry.currentLargest == nil || magnitude > (entry.currentLargest?.amount ?? 0) {
                    entry.currentLargest = (tx.id, magnitude)
                }
            }
            byCategory[key] = entry
        }

        var out: [ProactiveSignal] = []
        for (category, weeks) in byCategory {
            let current = weeks.buckets[0] ?? 0
            guard current > 0 else { continue }

            // Baseline series across the trailing weeks (absent weeks are real
            // zeros for a weekly cadence).
            let baseline: [Double] = (1...configuration.historyWeeks).map { weeks.buckets[$0] ?? 0 }
            let activeWeeks = baseline.filter { $0 > 0 }.count
            guard activeWeeks >= configuration.minimumActiveWeeks else { continue }

            let mean = baseline.reduce(0, +) / Double(baseline.count)
            let stdev = sampleStandardDeviation(baseline, mean: mean)
            guard stdev > 0 else { continue }

            let z = (current - mean) / stdev
            guard z >= configuration.anomalyZThreshold, current > mean else { continue }

            let weekStart = cal.startOfDay(for: currentWeekStart)
            let multiple = mean > 0 ? (current / mean) : 0
            out.append(ProactiveSignal(
                id: "proactive.anomaly.\(category).\(Int(weekStart.timeIntervalSince1970))",
                kind: .anomalousSpend,
                headline: "Unusual \(category) spending",
                body: "You've spent \(formatCurrency(Decimal(current))) on \(category) this week — about \(String(format: "%.1f", multiple))x your usual \(formatCurrency(Decimal(mean))).",
                subjectId: weeks.currentLargest?.id,
                date: snapshot.now,
                severity: z >= configuration.anomalyAlertZ ? .alert : .warning
            ))
        }
        return out
    }

    // MARK: - Helpers

    static func ranked(_ signals: [ProactiveSignal]) -> [ProactiveSignal] {
        signals.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity.rank > rhs.severity.rank
            }
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.id < rhs.id
        }
    }

    static func sampleStandardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sumSquares = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sumSquares / Double(values.count - 1)).squareRoot()
    }
}
