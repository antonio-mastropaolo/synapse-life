import XCTest
import Foundation
import SwiftData
@testable import Intelligence
import Models
import Persistence

final class ToolCallRegistryTests: XCTestCase {

    @MainActor
    func test_dispatch_getTransactions_returnsCount() async throws {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        let txStore = TransactionStore(modelContainer: container)
        let acctStore = AccountStore(modelContainer: container)
        let invStore = InvestmentStore(modelContainer: container)

        // Seed 10 transactions across April 2026.
        let calendar = Calendar(identifier: .gregorian)
        let dateFor: (Int) -> Date = { day in
            calendar.date(from: DateComponents(
                timeZone: TimeZone(identifier: "UTC"),
                year: 2026, month: 4, day: day
            ))!
        }
        let seeds: [Transaction] = (1...10).map { i in
            Transaction(
                id: "tx-\(i)",
                accountId: "acct-1",
                accountName: "Checking",
                amount: Decimal(-Double(i) * 5),
                currency: "USD",
                date: dateFor(i),
                name: "Merchant \(i)",
                merchantName: "M\(i)",
                category: .knownCategory("Food"),
                subcategory: nil,
                pending: false
            )
        }
        _ = try await txStore.upsertAll(seeds)

        let registry = ToolCallRegistry(
            accountStore: acctStore,
            transactionStore: txStore,
            investmentStore: invStore
        )

        let json = try await registry.dispatch(
            "get_transactions",
            args: ["start": "2026-04-01", "end": "2026-05-01"]
        )

        // Decode and assert shape + count.
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["count"] as? Int, 10)
        let rows = obj["transactions"] as! [[String: Any]]
        XCTAssertEqual(rows.count, 10)
        // Every row must carry an id, a date, and a name.
        for row in rows {
            XCTAssertNotNil(row["id"] as? String)
            XCTAssertNotNil(row["date"] as? String)
            XCTAssertNotNil(row["name"] as? String)
        }
    }

    @MainActor
    func test_dispatch_getTransactions_categoryFilter() async throws {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        let txStore = TransactionStore(modelContainer: container)
        let acctStore = AccountStore(modelContainer: container)
        let invStore = InvestmentStore(modelContainer: container)

        let cal = Calendar(identifier: .gregorian)
        let d: (Int) -> Date = { day in
            cal.date(from: DateComponents(
                timeZone: TimeZone(identifier: "UTC"),
                year: 2026, month: 4, day: day
            ))!
        }
        let mix: [Transaction] = [
            tx(id: "1", date: d(2), category: "Food"),
            tx(id: "2", date: d(3), category: "Food"),
            tx(id: "3", date: d(4), category: "Travel"),
            tx(id: "4", date: d(5), category: "Travel"),
            tx(id: "5", date: d(6), category: "Food")
        ]
        _ = try await txStore.upsertAll(mix)

        let registry = ToolCallRegistry(
            accountStore: acctStore,
            transactionStore: txStore,
            investmentStore: invStore
        )

        let json = try await registry.dispatch(
            "get_transactions",
            args: ["start": "2026-04-01", "end": "2026-05-01", "category": "Food"]
        )
        let obj = try JSONSerialization.jsonObject(
            with: json.data(using: .utf8)!
        ) as! [String: Any]
        XCTAssertEqual(obj["count"] as? Int, 3)
    }

    @MainActor
    func test_dispatch_getAccounts_returnsRows() async throws {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        let txStore = TransactionStore(modelContainer: container)
        let acctStore = AccountStore(modelContainer: container)
        let invStore = InvestmentStore(modelContainer: container)

        _ = try await acctStore.upsert(FinanceAccount(
            id: "a-1",
            institutionId: "inst-1",
            institutionName: "Test Bank",
            name: "Checking",
            officialName: nil,
            mask: "1234",
            kind: .checking,
            currency: "USD",
            currentBalance: Decimal(100),
            availableBalance: Decimal(95),
            limitAmount: nil,
            balanceCapturedAt: nil
        ))

        let registry = ToolCallRegistry(
            accountStore: acctStore,
            transactionStore: txStore,
            investmentStore: invStore
        )
        let json = try await registry.dispatch("get_accounts", args: [:])
        let obj = try JSONSerialization.jsonObject(
            with: json.data(using: .utf8)!
        ) as! [String: Any]
        let rows = obj["accounts"] as! [[String: Any]]
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["id"] as? String, "a-1")
    }

    @MainActor
    func test_dispatch_investments_throwsNotImplemented() async throws {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        let txStore = TransactionStore(modelContainer: container)
        let acctStore = AccountStore(modelContainer: container)
        let invStore = InvestmentStore(modelContainer: container)

        let registry = ToolCallRegistry(
            accountStore: acctStore,
            transactionStore: txStore,
            investmentStore: invStore
        )
        do {
            _ = try await registry.dispatch("get_investments", args: [:])
            XCTFail("expected throw")
        } catch LLMError.toolNotImplemented {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func test_dispatch_recurrings_returnsRowsFromStore() async throws {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        let txStore = TransactionStore(modelContainer: container)
        let acctStore = AccountStore(modelContainer: container)
        let invStore = InvestmentStore(modelContainer: container)
        let recStore = RecurringStore(modelContainer: container)

        let when = Date(timeIntervalSince1970: 1_779_840_000)
        _ = try await recStore.upsert(Recurring(
            id: "recurring.netflix",
            merchant: "Netflix",
            category: "subscriptions",
            medianAmount: Decimal(string: "15.49")!,
            cadenceDays: 30,
            lastSeen: when.addingTimeInterval(-30 * 86_400),
            predictedNext: when,
            occurrenceCount: 5,
            confidence: 0.92,
            transactionIds: ["t1", "t2", "t3", "t4", "t5"],
            isIncome: false
        ))

        let registry = ToolCallRegistry(
            accountStore: acctStore,
            transactionStore: txStore,
            investmentStore: invStore,
            recurringStore: recStore
        )
        let json = try await registry.dispatch("get_recurrings", args: [:])
        let obj = try JSONSerialization.jsonObject(
            with: json.data(using: .utf8)!
        ) as! [String: Any]
        XCTAssertEqual(obj["count"] as? Int, 1)
        let rows = obj["recurrings"] as! [[String: Any]]
        XCTAssertEqual(rows.first?["merchant"] as? String, "Netflix")
        XCTAssertEqual(rows.first?["category"] as? String, "subscriptions")
        XCTAssertEqual(rows.first?["cadenceDays"] as? Int, 30)
    }

    @MainActor
    func test_dispatch_recurrings_throwsWhenNoStore() async throws {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        let registry = ToolCallRegistry(
            accountStore: AccountStore(modelContainer: container),
            transactionStore: TransactionStore(modelContainer: container),
            investmentStore: InvestmentStore(modelContainer: container)
        )
        do {
            _ = try await registry.dispatch("get_recurrings", args: [:])
            XCTFail("expected throw")
        } catch LLMError.toolNotImplemented {
            // expected — degrades gracefully when no RecurringStore is wired.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_defaultTools_listsFourTools() {
        let tools = ToolCallRegistry.defaultTools()
        XCTAssertEqual(tools.count, 4)
        XCTAssertEqual(Set(tools.map(\.name)), [
            "get_accounts",
            "get_transactions",
            "get_investments",
            "get_recurrings"
        ])
    }

    // MARK: - Helpers

    private func tx(id: String, date: Date, category: String) -> Transaction {
        Transaction(
            id: id,
            accountId: "acct-1",
            accountName: "Checking",
            amount: Decimal(-10),
            currency: "USD",
            date: date,
            name: "tx-\(id)",
            merchantName: nil,
            category: .knownCategory(category),
            subcategory: nil,
            pending: false
        )
    }
}
