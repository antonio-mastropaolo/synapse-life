import Foundation
import Observation
import Models

/// One row in the Categories list. `spend` is the absolute outflow sum
/// in the current month for transactions resolved to this id. `spark` is
/// the per-day series used to render the tiny chart on the right.
public struct CategoryRow: Sendable, Equatable, Identifiable {
    public let id: CategoryID
    public let displayName: String
    public let emoji: String
    public let spend: Decimal
    public let spark: [Double]

    public init(id: CategoryID, displayName: String, emoji: String, spend: Decimal, spark: [Double]) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.spend = spend
        self.spark = spark
    }
}

@MainActor
@Observable
public final class CategoriesViewModel {

    /// Transactions to project. The view owns the source — typically the
    /// same ledger feeding [[FinanceTransactionsViewModel]] — and reassigns
    /// when filters change.
    public private(set) var rows: [CategoryRow] = []

    private let store: CategoryStore

    /// Current month bounds. Held as a getter so tests can swap a fixed
    /// "now" without rebuilding the world.
    private var nowProvider: @Sendable () -> Date

    public init(
        store: CategoryStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.nowProvider = now
    }

    public func project(transactions: [Transaction]) async {
        let customs = await store.customRecords()
        let customsByID = Dictionary(uniqueKeysWithValues: customs.map { (CategoryID.custom(slug: $0.slug), $0) })

        // Bucket by canonical id, summing absolute outflow only.
        var bucketSpend: [CategoryID: Decimal] = [:]
        var bucketSpark: [CategoryID: [Double]] = [:]

        let cal = Calendar(identifier: .gregorian)
        let now = nowProvider()
        let monthInterval = cal.dateInterval(of: .month, for: now)
        let dayCount = max(1, cal.range(of: .day, in: .month, for: now)?.count ?? 30)

        for tx in transactions {
            guard let interval = monthInterval, interval.contains(tx.date) else { continue }
            guard let amount = tx.amount else { continue }
            // Outflows only — credits don't add to category spend.
            guard amount < 0 else { continue }
            let abs = amount * Decimal(-1)
            let id = CategoryResolver.resolve(tx)
            bucketSpend[id, default: 0] += abs

            let day = max(0, min(dayCount - 1, (cal.dateComponents([.day], from: tx.date).day ?? 1) - 1))
            var series = bucketSpark[id, default: Array(repeating: 0.0, count: dayCount)]
            series[day] += NSDecimalNumber(decimal: abs).doubleValue
            bucketSpark[id] = series
        }

        // Stable order: defaults first, then customs (matches store.categories()).
        let allCats = await store.categories()
        let result: [CategoryRow] = allCats.map { id in
            let name: String
            let emoji: String
            if case .custom = id, let rec = customsByID[id] {
                name = rec.displayName
                emoji = rec.emoji
            } else {
                name = id.displayName
                emoji = id.defaultEmoji
            }
            return CategoryRow(
                id: id,
                displayName: name,
                emoji: emoji,
                spend: bucketSpend[id] ?? 0,
                spark: bucketSpark[id] ?? Array(repeating: 0.0, count: dayCount)
            )
        }

        self.rows = result
    }
}
