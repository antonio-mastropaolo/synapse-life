import Foundation
import Models
import Networking
import Features
import Persistence

/// Live composition for the Activity surface.
///
/// Reads the user-visible state of the cockpit view models — the rows the
/// finance VM has already loaded, the detector's recurrings, the durable
/// proactive feed — and folds them into a single `ActivitySnapshot`. Falls
/// through to `LifeAPI.entries(cursor:)` for server-side digest rows when
/// the route is live; tolerates failure (an offline server should not break
/// the Activity surface).
public actor LiveActivitySource: ActivitySource {

    private let lifeAPI: LifeAPI
    private let txnsProvider: @Sendable () async -> [Transaction]
    private let recurringsProvider: @Sendable () async -> [Recurring]
    private let signalsProvider: @Sendable () async -> [ProactiveSignal]

    public init(
        lifeAPI: LifeAPI,
        transactions: @escaping @Sendable () async -> [Transaction],
        recurrings: @escaping @Sendable () async -> [Recurring],
        signals: @escaping @Sendable () async -> [ProactiveSignal]
    ) {
        self.lifeAPI = lifeAPI
        self.txnsProvider = transactions
        self.recurringsProvider = recurrings
        self.signalsProvider = signals
    }

    public func snapshot(now: Date) async -> ActivitySnapshot {
        async let txns      = txnsProvider()
        async let recurs    = recurringsProvider()
        async let sigs      = signalsProvider()
        async let digests   = fetchDigests()

        return ActivitySnapshot(
            transactions: await txns,
            recurrings: await recurs,
            signals: await sigs,
            digests: await digests
        )
    }

    private func fetchDigests() async -> [LifeEntry] {
        do {
            return try await lifeAPI.entries(cursor: nil).entries.filter {
                $0.kind == .digest || $0.kind == .streak
            }
        } catch {
            return []
        }
    }
}
