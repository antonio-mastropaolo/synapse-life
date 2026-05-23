import Foundation
import Testing
@testable import Models
@testable import Features

/// Test stub router — records the prompt it was handed and emits a
/// fixed answer one chunk at a time, then `.done`.
private struct ScriptedRouter: IntelligenceRouter {
    let route: IntelligenceRoute
    let chunks: [String]

    func stream(
        prompt: String,
        context: AskContext
    ) -> AsyncThrowingStream<IntelligenceDelta, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            Task {
                for c in chunks {
                    continuation.yield(.text(c))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }
}

@Suite("IntelligenceRouter")
struct IntelligenceRouterTests {

    @Test func defaultRouterPicksAppleIntelligenceWhenForced() {
        let apple = ScriptedRouter(route: .appleIntelligence, chunks: ["A "])
        let server = ScriptedRouter(route: .server, chunks: ["S "])
        let router = DefaultIntelligenceRouter(
            appleIntelligence: apple,
            server: server,
            forceRoute: .appleIntelligence
        )
        #expect(router.route == .appleIntelligence)
    }

    @Test func defaultRouterPicksServerWhenForced() {
        let apple = ScriptedRouter(route: .appleIntelligence, chunks: ["A "])
        let server = ScriptedRouter(route: .server, chunks: ["S "])
        let router = DefaultIntelligenceRouter(
            appleIntelligence: apple,
            server: server,
            forceRoute: .server
        )
        #expect(router.route == .server)
    }

    @Test func defaultRouterChoosesByOSAvailabilityWhenNotForced() {
        let apple = ScriptedRouter(route: .appleIntelligence, chunks: [])
        let server = ScriptedRouter(route: .server, chunks: [])
        let router = DefaultIntelligenceRouter(
            appleIntelligence: apple,
            server: server,
            forceRoute: nil
        )
        let expected: IntelligenceRoute = DefaultIntelligenceRouter.systemPicksAppleIntelligence()
            ? .appleIntelligence
            : .server
        #expect(router.route == expected)
    }

    @Test func serverIntelligenceRouterBridgesAskAPIDeltas() async throws {
        let askAPI = LocalStubAskAPI()
        let router = ServerIntelligenceRouter(askAPI: askAPI)
        let ctx = AskContext(accounts: [], recentTransactions: [])
        var collected = ""
        for try await delta in router.stream(prompt: "net worth?", context: ctx) {
            if case .text(let s) = delta { collected += s }
            if case .done = delta { break }
        }
        #expect(!collected.isEmpty)
    }

    @Test func citationsForLargestPickTopThreeOutflows() {
        let txs: [Transaction] = [
            Transaction(id: "a", accountId: "x", accountName: "Chk", amount: -10, currency: "USD", date: Date(), name: "Coffee", merchantName: nil, category: .knownCategory("Dining"), subcategory: nil, pending: false),
            Transaction(id: "b", accountId: "x", accountName: "Chk", amount: -500, currency: "USD", date: Date(), name: "Rent", merchantName: nil, category: .knownCategory("Housing"), subcategory: nil, pending: false),
            Transaction(id: "c", accountId: "x", accountName: "Chk", amount: -200, currency: "USD", date: Date(), name: "Groceries", merchantName: nil, category: .knownCategory("Groceries"), subcategory: nil, pending: false),
            Transaction(id: "d", accountId: "x", accountName: "Chk", amount: -50, currency: "USD", date: Date(), name: "Gas", merchantName: nil, category: .knownCategory("Transport"), subcategory: nil, pending: false)
        ]
        let ctx = AskContext(accounts: [], recentTransactions: txs)
        let cites = AskCitationsExtractor.extract(question: "what was my largest expense?", context: ctx)
        #expect(cites.count == 3)
        #expect(cites.first?.targetId == "b") // Rent is largest
    }

    @Test func citationsForCheckingPickAccount() {
        let account = FinanceAccount(
            id: "chk-1",
            institutionId: "i", institutionName: "Bank",
            name: "Adv Plus Banking", officialName: nil, mask: "1234",
            kind: .checking, currency: "USD",
            currentBalance: 1000, availableBalance: 1000, limitAmount: nil, balanceCapturedAt: nil
        )
        let ctx = AskContext(accounts: [account], recentTransactions: [])
        let cites = AskCitationsExtractor.extract(question: "what is my checking balance?", context: ctx)
        #expect(cites.count == 1)
        #expect(cites.first?.kind == .account)
        #expect(cites.first?.targetId == "chk-1")
    }
}
