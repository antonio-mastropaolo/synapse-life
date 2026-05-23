import Foundation
import Testing
@testable import Models
@testable import Features

private func ctx(accounts: [FinanceAccount] = [], txs: [Transaction] = []) -> AskContext {
    AskContext(accounts: accounts, recentTransactions: txs)
}

private func makeAccount(
    name: String = "Checking",
    kind: AccountKind = .checking,
    balance: Decimal = 1000
) -> FinanceAccount {
    FinanceAccount(
        id: UUID().uuidString, institutionId: "x", institutionName: "B",
        name: name, officialName: nil, mask: "1234", kind: kind,
        currency: "USD", currentBalance: balance, availableBalance: balance,
        limitAmount: nil, balanceCapturedAt: nil
    )
}

private func makeTx(amount: Decimal, name: String = "X", pending: Bool = false) -> Transaction {
    Transaction(
        id: UUID().uuidString, accountId: "a", accountName: "A",
        amount: amount, currency: "USD", date: Date(),
        name: name, merchantName: nil, category: .unknown,
        subcategory: nil, pending: pending
    )
}

@Suite("AskStub")
struct AskStubTests {

    @Test func netWorthQuestionReturnsNetWorthSentence() {
        let answer = LocalStubAskAPI.composeAnswer(
            question: "what is my net worth",
            context: ctx(accounts: [
                makeAccount(name: "Chk", kind: .checking, balance: 1000),
                makeAccount(name: "Crd", kind: .credit, balance: 200)
            ])
        )
        #expect(answer.contains("net worth"))
        // 1000 - 200 = 800
        #expect(answer.contains("800"))
    }

    @Test func spendQuestionReturnsRecentSpend() {
        let answer = LocalStubAskAPI.composeAnswer(
            question: "how much did I spend",
            context: ctx(txs: [makeTx(amount: -50), makeTx(amount: -25)])
        )
        #expect(answer.contains("75"))
        #expect(answer.contains("transactions"))
    }

    @Test func largestOutflowAnswerNamesTheRow() {
        let answer = LocalStubAskAPI.composeAnswer(
            question: "show my largest expense this week",
            context: ctx(txs: [makeTx(amount: -10, name: "Coffee"), makeTx(amount: -250, name: "Rent")])
        )
        #expect(answer.contains("Rent"))
        #expect(answer.contains("250"))
    }

    @Test func defaultBranchEchoesQuestion() {
        let answer = LocalStubAskAPI.composeAnswer(
            question: "what color is the sky",
            context: ctx(accounts: [makeAccount(balance: 500)])
        )
        #expect(answer.contains("what color is the sky"))
    }

    @Test func streamYieldsTokensInOrder() async throws {
        let api = LocalStubAskAPI()
        let stream = api.ask(question: "what is my net worth", context: ctx(
            accounts: [makeAccount(balance: 100)]
        ))
        var collected = ""
        for try await delta in stream {
            switch delta {
            case .text(let s): collected += s
            case .done: break
            case .error: Issue.record("unexpected error delta")
            }
            if collected.count > 200 { break }
        }
        #expect(collected.contains("net worth"))
    }
}
