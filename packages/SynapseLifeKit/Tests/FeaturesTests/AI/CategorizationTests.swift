import Foundation
import Testing
@testable import Models
@testable import Features

@Suite("Categorization")
struct CategorizationTests {

    @Test func transfersMatchZelle() {
        let g = LocalStubCategorizationAPI.classify(name: "ZELLE TO JANE")
        #expect(g.label == "Transfers")
        #expect(g.confidence > 0.9)
    }

    @Test func loansMatchAffirm() {
        let g = LocalStubCategorizationAPI.classify(name: "AFFIRM PAYMENT")
        #expect(g.label == "Loans")
    }

    @Test func entertainmentMatchesStreaming() {
        let g = LocalStubCategorizationAPI.classify(name: "NETFLIX.COM")
        #expect(g.label == "Entertainment")
    }

    @Test func incomeMatchesPayroll() {
        let g = LocalStubCategorizationAPI.classify(name: "DIRECT DEP PAYROLL")
        #expect(g.label == "Income")
    }

    @Test func feesMatchOverdraft() {
        let g = LocalStubCategorizationAPI.classify(name: "OVERDRAFT FEE")
        #expect(g.label == "Fees")
    }

    @Test func unrecognizedFallsBackToServerLabel() {
        let g = LocalStubCategorizationAPI.classify(name: "OBSCURE VENDOR XYZ", fallback: "Shopping")
        #expect(g.label == "Shopping")
        #expect(g.confidence < 0.5)
    }

    @Test func unrecognizedWithoutFallbackBecomesOther() {
        let g = LocalStubCategorizationAPI.classify(name: "OBSCURE VENDOR XYZ", fallback: "Uncategorized")
        #expect(g.label == "Other")
    }

    @Test func diningMatchesStarbucks() async {
        let api = LocalStubCategorizationAPI()
        let tx = Transaction(
            id: "t1", accountId: "a", accountName: "Acct",
            amount: -5, currency: "USD", date: Date(),
            name: "STARBUCKS #1234", merchantName: nil,
            category: .unknown, subcategory: nil, pending: false
        )
        let g = await api.categorize(tx)
        #expect(g.label == "Dining")
    }
}
