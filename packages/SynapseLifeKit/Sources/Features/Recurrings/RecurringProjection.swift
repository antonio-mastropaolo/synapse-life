import Foundation
import Models

/// Bridges the in-memory `DetectedRecurring` (which carries the `Features`-level
/// `CategoryID`) to the Sendable `Models.Recurring` that persists and crosses
/// actor boundaries. The category collapses to its `CategoryID` slug; a
/// consumer re-hydrates the enum via `CategoryID.from(slug:)`.
public extension DetectedRecurring {

    /// Project to the persistable DTO. `isIncome` is supplied by the caller
    /// because `DetectedRecurring` doesn't itself record the debit/credit flow
    /// — the detector emits debits via `detectRecurrings` and credits via
    /// `detectIncomeRecurrings`. Income rows get a distinct id namespace so a
    /// recurring credit never collides with a recurring debit of the same
    /// merchant.
    func asRecurring(isIncome: Bool = false) -> Recurring {
        let slug = merchant
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let projectedId = isIncome ? "recurring.income.\(slug)" : "recurring.\(slug)"
        return Recurring(
            id: projectedId,
            merchant: merchant,
            category: category.slug,
            medianAmount: medianAmount,
            cadenceDays: cadenceDays,
            lastSeen: lastSeen,
            predictedNext: predictedNext,
            occurrenceCount: occurrenceCount,
            confidence: confidence,
            transactionIds: transactionIds,
            isIncome: isIncome
        )
    }
}

public extension Recurring {

    /// Reverse bridge: hydrate a `DetectedRecurring` from a persisted
    /// `Recurring`. Used on cold start so the Recurrings surface can paint
    /// last-known rows from the store before a live transaction refresh
    /// recomputes them. The category slug re-hydrates through
    /// `CategoryID.from(slug:)` (an unknown slug round-trips to
    /// `.custom(slug:)`, never lossy).
    func asDetected() -> DetectedRecurring {
        DetectedRecurring(
            merchant: merchant,
            category: CategoryID.from(slug: category),
            medianAmount: medianAmount,
            cadenceDays: cadenceDays,
            lastSeen: lastSeen,
            predictedNext: predictedNext,
            occurrenceCount: occurrenceCount,
            confidence: confidence,
            transactionIds: transactionIds
        )
    }
}
