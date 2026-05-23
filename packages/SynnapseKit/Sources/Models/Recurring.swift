import Foundation

/// One detected recurring charge (or recurring credit, for income), in its
/// Sendable wire/persistence shape. The `Features/Recurrings` detector infers
/// these in memory as `DetectedRecurring`; this is the type that crosses actor
/// boundaries, persists via `PersistedRecurring`, and feeds the agent's
/// `get_recurrings` tool.
///
/// `category` is the `CategoryID` slug as a plain string — `Models` cannot
/// depend on the `Features`-level `CategoryID` enum, and the slug round-trips
/// losslessly through `CategoryID.from(slug:)`. `id` is stable across
/// re-derivations so a periodic re-run dedups against persisted rows rather
/// than duplicating a merchant's row every pass. Income recurrings carry a
/// distinct id namespace so they never collide with a debit of the same name.
public struct Recurring: Sendable, Hashable, Identifiable, Codable {

    public let id: String
    public let merchant: String
    /// `CategoryID` slug (e.g. `"subscriptions"`, `"restaurants"`). A consumer
    /// in `Features` re-hydrates the enum via `CategoryID.from(slug:)`.
    public let category: String
    public let medianAmount: Decimal
    /// Snapped cadence in days (7 / 14 / 30 / 90 / 365).
    public let cadenceDays: Int
    public let lastSeen: Date
    public let predictedNext: Date
    public let occurrenceCount: Int
    /// 0..1 — tighter cadence + more samples scores higher.
    public let confidence: Double
    /// Transaction ids that justified the detection.
    public let transactionIds: [String]
    /// `true` when this is a recurring credit (income) rather than a debit.
    public let isIncome: Bool

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
        isIncome: Bool = false
    ) {
        self.id = id
        self.merchant = merchant
        self.category = category
        self.medianAmount = medianAmount
        self.cadenceDays = cadenceDays
        self.lastSeen = lastSeen
        self.predictedNext = predictedNext
        self.occurrenceCount = occurrenceCount
        self.confidence = confidence
        self.transactionIds = transactionIds
        self.isIncome = isIncome
    }
}
