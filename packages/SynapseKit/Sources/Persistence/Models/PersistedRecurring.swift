import Foundation
import SwiftData
import Models

/// SwiftData mirror of `Recurring`. Persisting detected recurrings lets a
/// periodic re-derivation dedup against rows the user has already seen and lets
/// the agent's `get_recurrings` tool answer from the store rather than
/// re-running the detector on every turn.
///
/// `medianAmount` is persisted as a canonical decimal String (`medianAmountRaw`)
/// for the same reason `PersistedTransaction.amount` is — SwiftData routes
/// `Decimal` through `Double` and drops precision past ~15 significant figures;
/// the String round-trip via `Decimal.description` / `Decimal(string:)` is
/// base-10 and exact. `category` holds the `CategoryID` slug verbatim.
@Model
public final class PersistedRecurring {

    @Attribute(.unique) public var id: String

    public var merchant: String
    public var category: String

    /// Canonical decimal String backing for `medianAmount`.
    public var medianAmountRaw: String

    /// Projected through `medianAmountRaw` to dodge SwiftData's
    /// `Decimal`-via-`Double` precision loss.
    public var medianAmount: Decimal {
        get { Decimal(string: medianAmountRaw) ?? .zero }
        set { medianAmountRaw = newValue.description }
    }

    public var cadenceDays: Int
    public var lastSeen: Date
    public var predictedNext: Date
    public var occurrenceCount: Int
    public var confidence: Double
    public var transactionIds: [String]
    public var isIncome: Bool

    /// Wall-clock instant this row was last written from a detector re-run.
    public var lastSyncedAt: Date

    public init(
        id: String,
        merchant: String,
        category: String,
        medianAmount: Decimal,
        cadenceDays: Int,
        lastSeen: Date,
        predictedNext: Date,
        occurrenceCount: Int,
        confidence: Double,
        transactionIds: [String],
        isIncome: Bool,
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.merchant = merchant
        self.category = category
        self.medianAmountRaw = medianAmount.description
        self.cadenceDays = cadenceDays
        self.lastSeen = lastSeen
        self.predictedNext = predictedNext
        self.occurrenceCount = occurrenceCount
        self.confidence = confidence
        self.transactionIds = transactionIds
        self.isIncome = isIncome
        self.lastSyncedAt = lastSyncedAt
    }
}
