import Foundation
import Models

/// Pure reducer. Composes the user's recent financial activity from the
/// three substrate sources — transactions, recurrings, and proactive
/// signals — into a single reverse-chronological `[LifeEntry]` feed.
/// Optionally folds in server-side digest entries supplied by `LifeAPI`.
///
/// Dedup rules avoid telling the same story twice:
/// - A transaction that already belongs to a recurring's
///   `transactionIds` is suppressed in favor of the recurring entry
///   (the recurring explains the pattern; the bare transaction is noise).
/// - A recurring whose id is referenced by an `upcomingBill`
///   signal's `subjectId` is suppressed in favor of the signal (the
///   signal carries explanation text the recurring does not).
public enum ActivityComposer {

    public static func compose(
        transactions: [Transaction],
        recurrings: [Recurring],
        signals: [ProactiveSignal],
        digests: [LifeEntry] = [],
        now: Date = Date(),
        limit: Int = 100
    ) -> [LifeEntry] {
        let txnsCoveredByRecurring: Set<String> = Set(
            recurrings.flatMap(\.transactionIds)
        )
        let recurringIdsCoveredBySignal: Set<String> = Set(
            signals.compactMap { sig in
                guard sig.kind == .upcomingBill, let subject = sig.subjectId else { return nil }
                return subject
            }
        )

        var entries: [LifeEntry] = []
        entries.reserveCapacity(transactions.count + recurrings.count + signals.count + digests.count)

        for s in signals {
            entries.append(LifeEntry(
                id: "signal:\(s.id)",
                timestamp: s.date,
                kind: mapSignalKind(s.kind),
                text: s.headline,
                metadata: signalMetadata(s)
            ))
        }

        for r in recurrings where r.predictedNext > now {
            if recurringIdsCoveredBySignal.contains(r.id) { continue }
            entries.append(LifeEntry(
                id: "bill:\(r.id)",
                timestamp: r.predictedNext,
                kind: .bill,
                text: composeRecurringText(r),
                metadata: ["recurringId": r.id, "merchant": r.merchant]
            ))
        }

        for tx in transactions where !tx.pending {
            if txnsCoveredByRecurring.contains(tx.id) { continue }
            entries.append(LifeEntry(
                id: "txn:\(tx.id)",
                timestamp: tx.date,
                kind: .transaction,
                text: composeTransactionText(tx),
                metadata: [
                    "txnId": tx.id,
                    "category": tx.category.displayLabel
                ]
            ))
        }

        for d in digests {
            entries.append(d)
        }

        return Array(
            entries
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(limit)
        )
    }

    /// Day bucket for the view's section grouping. `day` is the start of
    /// the calendar day; `entries` are reverse-chronological within it
    /// (matching the order produced by `compose`).
    public struct DayBucket: Sendable, Equatable, Identifiable {
        public let day: Date
        public let entries: [LifeEntry]
        public var id: Date { day }

        public init(day: Date, entries: [LifeEntry]) {
            self.day = day
            self.entries = entries
        }
    }

    public static func groupByDay(
        _ entries: [LifeEntry],
        calendar: Calendar = .current
    ) -> [DayBucket] {
        var byDay: [Date: [LifeEntry]] = [:]
        var order: [Date] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            if byDay[day] == nil {
                byDay[day] = []
                order.append(day)
            }
            byDay[day]?.append(entry)
        }
        return order.map { DayBucket(day: $0, entries: byDay[$0] ?? []) }
    }

    private static func mapSignalKind(_ k: ProactiveSignal.Kind) -> LifeEntryKind {
        switch k {
        case .upcomingBill:    return .bill
        case .newRecurring:    return .insight
        case .anomalousSpend:  return .warning
        }
    }

    private static func signalMetadata(_ s: ProactiveSignal) -> [String: String] {
        var meta: [String: String] = [
            "signalKind": s.kind.rawValue,
            "severity": s.severity.rawValue,
            "body": s.body
        ]
        if let subject = s.subjectId { meta["subjectId"] = subject }
        return meta
    }

    private static func composeTransactionText(_ tx: Transaction) -> String {
        let merchant = tx.merchantName?.isEmpty == false ? tx.merchantName! : tx.name
        return merchant
    }

    private static func composeRecurringText(_ r: Recurring) -> String {
        r.isIncome ? "\(r.merchant) — expected" : "\(r.merchant) — due"
    }
}
