import Foundation
import Testing
@testable import Models

/// Wire-level decoder tests for the unified transactions ledger. Mirrors
/// the shape produced by `/api/finance/transactions/route.ts`:
///   { "rows": [...], "count": N }
///
/// The route emits `date` as an ISO-string (`YYYY-MM-DD`) — but the native
/// client also accepts unix-seconds so the same model can decode the
/// per-account legacy shape and the upcoming `transaction_at` columns
/// without re-engineering the decoder.
@Suite("Transaction")
struct TransactionTests {

    @Test
    func decodesIsoDateAndSignedAmount() throws {
        let json: [String: Any] = [
            "rows": [[
                "id": "txn-1",
                "source": "bank",
                "accountId": "acc-cash",
                "accountName": "Chase Checking",
                "amount": -42.55,
                "currency": "USD",
                "date": "2026-04-12",
                "name": "BLUE BOTTLE COFFEE",
                "merchantName": "Blue Bottle Coffee",
                "category": "Food & Drink",
                "subcategory": "Coffee Shop",
                "pending": false
            ]],
            "count": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder.synnapseFinance.decode(TransactionsResponse.self, from: data)
        let txn = try #require(response.rows.first)
        #expect(txn.id == "txn-1")
        #expect(txn.accountId == "acc-cash")
        // Sign is preserved exactly: outflows stay negative.
        #expect(txn.amount == Decimal(string: "-42.55"))
        #expect(txn.currency == "USD")
        #expect(txn.category == .knownCategory("Food & Drink"))
        #expect(txn.merchantName == "Blue Bottle Coffee")
        #expect(txn.pending == false)
        // ISO date round-trips through Calendar w/o time-of-day drift. The
        // server emits a UTC day string; preserve that on read by querying
        // calendar components in UTC. Local-TZ rendering is the view layer's
        // job.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: txn.date)
        #expect(comps.year == 2026)
        #expect(comps.month == 4)
        #expect(comps.day == 12)
    }

    @Test
    func decodesUnixSecondsDateShape() throws {
        // Forward-compat: when the server emits a numeric `date` field
        // (unix seconds) — e.g. for the per-account endpoint that joins on
        // `transaction_at` — the decoder still works.
        let json: [String: Any] = [
            "rows": [[
                "id": "txn-2",
                "source": "bank",
                "accountId": "acc-cash",
                "accountName": "Chase Checking",
                "amount": 100.0,
                "currency": "USD",
                "date": 1_734_652_800, // 2024-12-20 UTC
                "name": "Salary",
                "merchantName": NSNull(),
                "category": "Income",
                "subcategory": NSNull(),
                "pending": false
            ]],
            "count": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder.synnapseFinance.decode(TransactionsResponse.self, from: data)
        let txn = try #require(response.rows.first)
        // Positive amount = credit; sign is preserved.
        #expect(txn.amount == Decimal(100))
        #expect(txn.date.timeIntervalSince1970 == 1_734_652_800)
    }

    @Test
    func unknownCategoryFallsBack() throws {
        let json: [String: Any] = [
            "rows": [[
                "id": "txn-x",
                "source": "email",
                "accountId": NSNull(),
                "accountName": NSNull(),
                "amount": -1.0,
                "currency": "USD",
                "date": "2026-04-01",
                "name": "Mystery",
                "merchantName": NSNull(),
                "category": NSNull(),
                "subcategory": NSNull(),
                "pending": false
            ]],
            "count": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder.synnapseFinance.decode(TransactionsResponse.self, from: data)
        let txn = try #require(response.rows.first)
        // Null/missing category → .unknown for forward-compat.
        #expect(txn.category == .unknown)
    }

    @Test
    func sendableEquatableIdentifiable() {
        let t = Transaction(
            id: "t1", accountId: "a", accountName: "A",
            amount: Decimal(-10), currency: "USD",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            name: "x", merchantName: nil,
            category: .unknown, subcategory: nil, pending: false
        )
        let t2 = t
        #expect(t == t2)
        #expect(t.id == "t1")
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        _ = requireSendable(t)
    }
}
