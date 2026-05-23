import Foundation
import Testing
@testable import Features
@testable import Models

/// Phase 4 — the proactive insights engine. `ProactiveAnalyzer` is a pure
/// function over an `AlertsSnapshot`; these tests pin its three signal kinds
/// (upcoming bill, new recurring, anomalous spend) and the dedup/rank
/// contract. Determinism comes from a fixed `now` and hand-built ledgers.
@Suite("ProactiveAnalyzer")
struct ProactiveAnalyzerTests {

    /// 2026-05-23, matching the project's reference "today".
    static let now = Date(timeIntervalSince1970: 1_779_840_000)

    private static let cal = Calendar(identifier: .gregorian)

    private func tx(
        id: String,
        amount: String,
        daysAgo: Double,
        merchant: String,
        category: String
    ) -> Transaction {
        let amt = Decimal(string: amount) ?? .zero
        return Transaction(
            id: id,
            accountId: "acc-1",
            accountName: "Checking",
            amount: amt,
            currency: "USD",
            date: Self.now.addingTimeInterval(-daysAgo * 86_400),
            name: merchant,
            merchantName: merchant,
            category: .knownCategory(category),
            subcategory: nil,
            pending: false
        )
    }

    /// Three ~30-day-spaced debits whose next predicted charge lands a few
    /// days out. Merchant is already known (`priorMerchants`), so it surfaces
    /// as an upcoming bill, not a new recurring.
    @Test
    func knownRecurringDueSoonSurfacesUpcomingBill() {
        let txns = [
            tx(id: "s1", amount: "-15.00", daysAgo: 86, merchant: "StreamCo", category: "Entertainment"),
            tx(id: "s2", amount: "-15.00", daysAgo: 56, merchant: "StreamCo", category: "Entertainment"),
            tx(id: "s3", amount: "-15.00", daysAgo: 26, merchant: "StreamCo", category: "Entertainment"),
        ]
        let snapshot = AlertsSnapshot(
            accounts: [],
            transactions: txns,
            priorMerchants: ["STREAMCO"],
            now: Self.now
        )
        let signals = ProactiveAnalyzer.analyze(snapshot: snapshot)
        let bills = signals.filter { $0.kind == .upcomingBill }
        #expect(bills.count == 1)
        #expect(bills.first?.headline.contains("StreamCo") == true)
        #expect(signals.contains { $0.kind == .newRecurring } == false)
    }

    /// Same cadence, but the merchant is unknown: it should read as a NEW
    /// recurring (more salient) and not double-surface as an upcoming bill.
    @Test
    func unknownRecurringSurfacesNewRecurringNotUpcoming() {
        let txns = [
            tx(id: "g1", amount: "-9.99", daysAgo: 86, merchant: "GymPlus", category: "Health"),
            tx(id: "g2", amount: "-9.99", daysAgo: 56, merchant: "GymPlus", category: "Health"),
            tx(id: "g3", amount: "-9.99", daysAgo: 26, merchant: "GymPlus", category: "Health"),
        ]
        let snapshot = AlertsSnapshot(
            accounts: [],
            transactions: txns,
            priorMerchants: [],
            now: Self.now
        )
        let signals = ProactiveAnalyzer.analyze(snapshot: snapshot)
        #expect(signals.contains { $0.kind == .newRecurring } == true)
        #expect(signals.contains { $0.kind == .upcomingBill } == false)
    }

    /// Six prior weeks of ~$50 dining with mild variance, then a $300 spike
    /// in the current week. The z-score should clear the threshold and the
    /// spike should surface as an alert-severity anomaly.
    @Test
    func currentWeekSpikeSurfacesAnomaly() {
        var txns: [Transaction] = []
        let baseline = ["40", "55", "48", "52", "45", "60"]
        for (i, amt) in baseline.enumerated() {
            // One debit per prior week, placed mid-week.
            let daysAgo = Double((i + 1) * 7 + 3)
            txns.append(tx(
                id: "d\(i)",
                amount: "-\(amt).00",
                daysAgo: daysAgo,
                merchant: "Cafe \(i)",
                category: "Dining"
            ))
        }
        // Current-week spike (2 days ago).
        txns.append(tx(id: "spike", amount: "-300.00", daysAgo: 2, merchant: "Steakhouse", category: "Dining"))

        let snapshot = AlertsSnapshot(accounts: [], transactions: txns, priorMerchants: [], now: Self.now)
        let signals = ProactiveAnalyzer.analyze(snapshot: snapshot)
        let anomalies = signals.filter { $0.kind == .anomalousSpend }
        #expect(anomalies.count == 1)
        #expect(anomalies.first?.severity == .alert)
        #expect(anomalies.first?.body.contains("Dining") == true)
    }

    /// Flat dining spend across every week including the current one must not
    /// trip the anomaly detector — no spike, no signal.
    @Test
    func stableSpendProducesNoAnomaly() {
        var txns: [Transaction] = []
        let weekly = ["40", "55", "48", "52", "45", "60", "50"]  // last entry = current week
        for (i, amt) in weekly.enumerated() {
            let daysAgo = Double(i * 7 + 2)
            txns.append(tx(
                id: "d\(i)",
                amount: "-\(amt).00",
                daysAgo: daysAgo,
                merchant: "Cafe \(i)",
                category: "Dining"
            ))
        }
        let snapshot = AlertsSnapshot(accounts: [], transactions: txns, priorMerchants: [], now: Self.now)
        let signals = ProactiveAnalyzer.analyze(snapshot: snapshot)
        #expect(signals.contains { $0.kind == .anomalousSpend } == false)
    }

    /// Signals carry stable ids (so a nightly re-run dedups against persisted
    /// rows) and are ranked alert > warning > info.
    @Test
    func signalsAreRankedAndStablyIdentified() {
        let txns = [
            tx(id: "g1", amount: "-9.99", daysAgo: 86, merchant: "GymPlus", category: "Health"),
            tx(id: "g2", amount: "-9.99", daysAgo: 56, merchant: "GymPlus", category: "Health"),
            tx(id: "g3", amount: "-9.99", daysAgo: 26, merchant: "GymPlus", category: "Health"),
        ]
        var spikeTxns = txns
        let baseline = ["40", "55", "48", "52", "45", "60"]
        for (i, amt) in baseline.enumerated() {
            spikeTxns.append(tx(
                id: "d\(i)",
                amount: "-\(amt).00",
                daysAgo: Double((i + 1) * 7 + 3),
                merchant: "Cafe \(i)",
                category: "Dining"
            ))
        }
        spikeTxns.append(tx(id: "spike", amount: "-300.00", daysAgo: 2, merchant: "Steakhouse", category: "Dining"))

        let snapshot = AlertsSnapshot(accounts: [], transactions: spikeTxns, priorMerchants: [], now: Self.now)
        let first = ProactiveAnalyzer.analyze(snapshot: snapshot)
        let second = ProactiveAnalyzer.analyze(snapshot: snapshot)

        // Determinism: identical ids across runs.
        #expect(first.map(\.id) == second.map(\.id))
        // Ranking: the alert-severity anomaly outranks the info-severity recurring.
        #expect(first.first?.severity == .alert)
        // No duplicate ids within one pass.
        #expect(Set(first.map(\.id)).count == first.count)
    }
}
