import Foundation
import Models

/// One detected recurring charge. The detector groups transactions by
/// normalized merchant name, requires ≥ 3 occurrences in the trailing
/// 180-day window, and classifies the cadence into a standard bucket
/// (7 / 14 / 30 / 90 / 365 days) when the median inter-arrival sits
/// within ±20% of the bucket. Outputs sorted by ascending
/// `predictedNext` so callers can use the slice directly as a "next
/// up" view.
///
/// Distinct from [[ForecastReducer.predictedRecurrings]]: that lighter
/// detector requires only 2 occurrences and is used to widen the
/// forecast's predicted-charges feed. This one is the canonical
/// source for the Recurrings and Subscriptions product surfaces, where
/// false positives hurt more than missed detections.
public struct DetectedRecurring: Sendable, Hashable, Identifiable {

    /// `merchant` is already lowercased + tail-stripped; we expose the
    /// display form so the UI doesn't re-normalize. The id is stable
    /// across runs because it derives from the normalized key.
    public var id: String { "recurring.\(merchant.lowercased().replacingOccurrences(of: " ", with: "-"))" }

    public let merchant: String
    public let category: CategoryID
    public let medianAmount: Decimal
    public let cadenceDays: Int
    public let lastSeen: Date
    public let predictedNext: Date
    public let occurrenceCount: Int
    /// 0..1 — derived from std-dev of inter-arrival times and the
    /// occurrence count. Higher = tighter cadence + more samples.
    public let confidence: Double
    /// The transaction ids that justified the detection — drives the
    /// "Last 6 occurrences" inspector pane.
    public let transactionIds: [String]

    public init(
        merchant: String,
        category: CategoryID,
        medianAmount: Decimal,
        cadenceDays: Int,
        lastSeen: Date,
        predictedNext: Date,
        occurrenceCount: Int,
        confidence: Double,
        transactionIds: [String]
    ) {
        self.merchant = merchant
        self.category = category
        self.medianAmount = medianAmount
        self.cadenceDays = cadenceDays
        self.lastSeen = lastSeen
        self.predictedNext = predictedNext
        self.occurrenceCount = occurrenceCount
        self.confidence = confidence
        self.transactionIds = transactionIds
    }
}

/// Pure-logic detector for recurring charges. Public so the
/// Subscriptions detector and the test suite can share the same code
/// path; the product entry points are `detectRecurrings(...)` and
/// (in the sibling module) `SubscriptionDetector.detect(...)`.
public enum RecurringDetector {

    /// Standard cadences we'll snap to. 90 days covers quarterly
    /// (insurance, some streaming services). 14 covers bi-weekly
    /// (payroll, a few gym memberships).
    public static let cadenceBuckets: [Int] = [7, 14, 30, 90, 365]

    /// Minimum sample size before we emit a detection. Three is the
    /// smallest n that lets us reject one-off noise and still pick up
    /// a brand-new monthly sub within ~90 days of its first charge.
    public static let minimumOccurrences: Int = 3

    /// Trailing window — anything older than this is ignored. 180 days
    /// is enough to see five monthly charges and one annual renewal
    /// in flight at any given time.
    public static let trailingWindowDays: Int = 180

    /// Cadence-bucket tolerance (±). A 27-day inter-arrival still
    /// classifies as monthly because the user pays on a calendar day,
    /// not on a 30-day stride.
    public static let bucketTolerance: Double = 0.20

    /// Detect recurring charges in `transactions`. Returns an empty
    /// array if no merchant clears the threshold. Only debits (amount
    /// < 0) are considered — see [[detectIncomeRecurrings]] for the
    /// credit-side equivalent used by [[BalanceProjection]].
    public static func detectRecurrings(
        transactions: [Transaction],
        today: Date = Date()
    ) -> [DetectedRecurring] {
        detect(transactions: transactions, today: today, sign: .debit)
    }

    /// Same algorithm against credits — recurring income.
    public static func detectIncomeRecurrings(
        transactions: [Transaction],
        today: Date = Date()
    ) -> [DetectedRecurring] {
        detect(transactions: transactions, today: today, sign: .credit)
    }

    enum Sign { case debit, credit }

    static func detect(
        transactions: [Transaction],
        today: Date,
        sign: Sign
    ) -> [DetectedRecurring] {
        let earliest = today.addingTimeInterval(-Double(trailingWindowDays) * 86_400)
        var byMerchant: [String: [Transaction]] = [:]
        for tx in transactions {
            guard let a = tx.amount, !tx.pending else { continue }
            switch sign {
            case .debit:  guard a < 0 else { continue }
            case .credit: guard a > 0 else { continue }
            }
            guard tx.date >= earliest, tx.date <= today else { continue }
            let key = normalize(tx.merchantName ?? tx.name)
            byMerchant[key, default: []].append(tx)
        }

        var out: [DetectedRecurring] = []
        for (key, rows) in byMerchant {
            guard rows.count >= minimumOccurrences else { continue }
            let sorted = rows.sorted { $0.date < $1.date }
            // Inter-arrival in days.
            var intervals: [Double] = []
            for i in 1..<sorted.count {
                intervals.append(sorted[i].date.timeIntervalSince(sorted[i - 1].date) / 86_400)
            }
            let medianInterval = median(intervals)
            guard let bucket = classifyCadence(medianInterval: medianInterval) else { continue }

            // Median amount across the window. Use median, not mean,
            // so an outlier renewal doesn't skew the predicted figure.
            let amounts = sorted.compactMap { $0.amount.map { absDecimal($0) } }
            let medianAmount = medianDecimal(amounts)

            let last = sorted.last!
            let predictedNext = last.date.addingTimeInterval(Double(bucket) * 86_400)

            // Confidence: 1.0 when std-dev is zero AND we have ≥ 6
            // samples; decays linearly with std-dev and with fewer
            // samples. Bounded to [0.4, 1.0] so the UI can paint a
            // "low-confidence" hint without ever going to zero.
            let stdev = sampleStdev(intervals)
            let tightness = max(0.0, 1.0 - (stdev / Double(bucket)) * 2.0)
            let sampleBoost = min(1.0, Double(sorted.count) / 6.0)
            let confidence = max(0.4, min(1.0, tightness * 0.7 + sampleBoost * 0.3))

            let displayMerchant = displayName(for: key, sample: sorted.first!)
            let category = resolveCategory(rows: sorted)

            out.append(DetectedRecurring(
                merchant: displayMerchant,
                category: category,
                medianAmount: medianAmount,
                cadenceDays: bucket,
                lastSeen: last.date,
                predictedNext: predictedNext,
                occurrenceCount: sorted.count,
                confidence: confidence,
                transactionIds: sorted.map(\.id)
            ))
        }

        return out.sorted { lhs, rhs in
            if lhs.predictedNext == rhs.predictedNext {
                return lhs.merchant < rhs.merchant
            }
            return lhs.predictedNext < rhs.predictedNext
        }
    }

    // MARK: - Normalization

    /// Strip the noisy bits banks append to a merchant string so that
    /// "AFFIRM * PAY R3H" and "AFFIRM * NETO" both collapse to
    /// "AFFIRM" only if it really is the same merchant. Today we
    /// strip the `*` suffix, trailing 4-digit tails (auth codes), and
    /// common ".com" / ".COM/BILL" suffixes. Casing is folded.
    public static func normalize(_ raw: String) -> String {
        var s = raw.uppercased()
        // Drop everything from the first `*` onward (auth code tails).
        if let star = s.firstIndex(of: "*") {
            s = String(s[..<star])
        }
        // Drop common payment-rail tags.
        for tag in ["RECURRING", "AUTOPAY", "ACH CREDIT", "ACH DEBIT", "ZELLE", "VENMO"] {
            s = s.replacingOccurrences(of: tag, with: "")
        }
        // Drop `.COM/BILL` and trailing `.COM`.
        s = s.replacingOccurrences(of: ".COM/BILL", with: "")
        s = s.replacingOccurrences(of: ".COM", with: "")
        // Drop trailing 4+ digit codes (e.g. "#1042").
        s = s.replacingOccurrences(
            of: #"\s*#?\d{3,}\s*$"#,
            with: "",
            options: .regularExpression
        )
        // Collapse whitespace.
        s = s.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Snap `medianInterval` to a standard cadence bucket if it's
    /// within ±20% of one; otherwise return nil so the merchant is
    /// rejected (irregular -> not really recurring).
    public static func classifyCadence(medianInterval: Double) -> Int? {
        for bucket in cadenceBuckets {
            let delta = abs(medianInterval - Double(bucket)) / Double(bucket)
            if delta <= bucketTolerance {
                return bucket
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func displayName(for normalizedKey: String, sample: Transaction) -> String {
        // Prefer the original merchantName/name if normalization didn't
        // strip too much (i.e. they're the same up to casing). Otherwise
        // fall back to the normalized key cased like a brand.
        let raw = (sample.merchantName ?? sample.name)
        let upperRaw = raw.uppercased()
        if upperRaw == normalizedKey {
            return raw
        }
        // Title-case the normalized key conservatively.
        return normalizedKey
            .split(separator: " ")
            .map { word -> String in
                let s = String(word)
                if s.allSatisfy({ $0.isNumber }) { return s }
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func resolveCategory(rows: [Transaction]) -> CategoryID {
        // Use the most-frequent server-supplied label; map onto the
        // small visible set used in the Categories surface.
        var counts: [String: Int] = [:]
        for r in rows {
            counts[r.category.displayLabel, default: 0] += 1
        }
        guard let label = counts.max(by: { $0.value < $1.value })?.key else {
            return .other
        }
        return mapLabel(label)
    }

    /// Public so the Subscriptions detector can re-use the mapping
    /// without depending on CategoryResolver (which carries SwiftUI).
    public static func mapLabel(_ label: String) -> CategoryID {
        switch label.uppercased() {
        case "SUBSCRIPTIONS", "SOFTWARE", "STREAMING":
            return .subscriptions
        case "RESTAURANTS", "FOOD AND DRINK", "DINING":
            return .restaurants
        case "GROCERIES":
            return .groceries
        case "LOANS", "BNPL":
            return .loans
        case "CLOTHING":
            return .clothing
        case "INCOME":
            return .income
        case "TRANSFER", "TRANSFERS":
            return .transfers
        case "PERSONAL CARE":
            return .personalCare
        case "ENTERTAINMENT":
            return .entertainment
        case "FEES":
            return .fees
        default:
            return .other
        }
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let mid = s.count / 2
        if s.count % 2 == 0 { return (s[mid - 1] + s[mid]) / 2 }
        return s[mid]
    }

    static func medianDecimal(_ values: [Decimal]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let mid = s.count / 2
        if s.count % 2 == 0 { return (s[mid - 1] + s[mid]) / 2 }
        return s[mid]
    }

    static func sampleStdev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquares = values.reduce(0) { acc, v in acc + (v - mean) * (v - mean) }
        return (sumSquares / Double(values.count - 1)).squareRoot()
    }
}

// `absDecimal(_:)` is defined elsewhere in Features (in
// `ForecastReducer.swift` private helpers, exposed at module scope).
// We reuse that one rather than redeclaring.
