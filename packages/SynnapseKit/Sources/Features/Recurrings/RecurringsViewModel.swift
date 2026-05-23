import Foundation
import Observation
import Models

/// View model for the Recurrings surface. Owns the detected list
/// (canonical truth from [[RecurringDetector]]) and a side-channel
/// [[RecurringStatusStore]] so the user can confirm / ignore each
/// detection. The view reads `sections` to render three collapsible
/// groups (Detected, Confirmed, Ignored).
@MainActor
@Observable
public final class RecurringsViewModel {

    public private(set) var recurrings: [DetectedRecurring] = []
    public private(set) var lastRefreshed: Date?

    /// Underlying transactions cache so the inspector pane can paint
    /// the per-merchant occurrence history without re-querying the
    /// finance VM.
    private var transactionsById: [String: Transaction] = [:]

    private let store: any RecurringStatusStoreProtocol
    /// Bumps every time the user toggles a status — drives SwiftUI
    /// re-renders since the store itself is intentionally not
    /// `@Observable`.
    public private(set) var statusVersion: Int = 0

    public init(store: any RecurringStatusStoreProtocol = RecurringStatusStore()) {
        self.store = store
    }

    public func refresh(transactions: [Transaction], today: Date = Date()) {
        self.recurrings = RecurringDetector.detectRecurrings(
            transactions: transactions, today: today
        )
        self.transactionsById = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        self.lastRefreshed = today
    }

    /// Cold-start hydration from a persisted source (the SwiftData
    /// `RecurringStore`, bridged through `Recurring.asDetected()`). Paints the
    /// surface with last-known rows before a live `refresh(transactions:)`
    /// recomputes them. Skipped when `detected` is empty so it never blanks an
    /// already-refreshed list. The per-merchant occurrence inspector stays
    /// empty until the first real `refresh` supplies transactions.
    public func hydrate(_ detected: [DetectedRecurring], at date: Date? = nil) {
        guard !detected.isEmpty else { return }
        self.recurrings = detected
        self.lastRefreshed = date
    }

    public func status(for r: DetectedRecurring) -> RecurringStatus {
        store.status(for: r.merchant)
    }

    public func setStatus(_ status: RecurringStatus, for r: DetectedRecurring) {
        store.setStatus(status, for: r.merchant)
        statusVersion += 1
    }

    /// The recurrings partitioned by their stored status.
    public var sections: (detected: [DetectedRecurring], confirmed: [DetectedRecurring], ignored: [DetectedRecurring]) {
        _ = statusVersion  // observation dependency
        var detected: [DetectedRecurring] = []
        var confirmed: [DetectedRecurring] = []
        var ignored: [DetectedRecurring] = []
        for r in recurrings {
            switch store.status(for: r.merchant) {
            case .detected:  detected.append(r)
            case .confirmed: confirmed.append(r)
            case .ignored:   ignored.append(r)
            }
        }
        return (detected, confirmed, ignored)
    }

    /// Sum of `medianAmount` across `confirmed + detected` rows —
    /// matches what the UI surfaces as "monthly cost" by collapsing
    /// each cadence into a monthly figure.
    public var monthlyEquivalentTotal: Decimal {
        recurrings
            .filter { store.status(for: $0.merchant) != .ignored }
            .reduce(Decimal.zero) { acc, r in
                acc + monthlyEquivalent(amount: r.medianAmount, cadenceDays: r.cadenceDays)
            }
    }

    /// Last N transactions that justified a recurring detection,
    /// newest first. Drives the macOS inspector pane.
    public func recentOccurrences(for r: DetectedRecurring, limit: Int = 6) -> [Transaction] {
        r.transactionIds
            .compactMap { transactionsById[$0] }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    private func monthlyEquivalent(amount: Decimal, cadenceDays: Int) -> Decimal {
        switch cadenceDays {
        case 7:   return amount * Decimal(30) / Decimal(7)
        case 14:  return amount * Decimal(30) / Decimal(14)
        case 30:  return amount
        case 90:  return amount / 3
        case 365: return amount / 12
        default:  return amount
        }
    }
}
