import Foundation
import Testing
@testable import Models
@testable import Features

private func makeTx(name: String, category: String = "Other") -> Transaction {
    return Transaction(
        id: UUID().uuidString,
        accountId: "acct",
        accountName: "Chk",
        amount: -10,
        currency: "USD",
        date: Date(),
        name: name,
        merchantName: nil,
        category: .knownCategory(category),
        subcategory: nil,
        pending: false
    )
}

@Suite("CategorizationTraining")
struct CategorizationTrainingTests {

    @Test func confidenceLevelMapsHigh() {
        let guess = CategoryGuess(label: "Dining", confidence: 0.9)
        #expect(guess.confidenceLevel == .high)
    }

    @Test func confidenceLevelMapsMedium() {
        let guess = CategoryGuess(label: "Other", confidence: 0.7)
        #expect(guess.confidenceLevel == .medium)
    }

    @Test func confidenceLevelMapsLow() {
        let guess = CategoryGuess(label: "Other", confidence: 0.3)
        #expect(guess.confidenceLevel == .low)
    }

    @Test func topKSuggestionsReturnsPrimaryFirst() async {
        let api = LocalStubCategorizationAPI()
        let tx = makeTx(name: "STARBUCKS")
        let suggestions = await api.suggestions(for: tx, top: 3)
        #expect(suggestions.count == 3)
        #expect(suggestions.first?.label == "Dining")
    }

    @Test func topKSuggestionsAlternativesHaveLowerConfidence() async {
        let api = LocalStubCategorizationAPI()
        let tx = makeTx(name: "NETFLIX")
        let suggestions = await api.suggestions(for: tx, top: 3)
        guard suggestions.count >= 2 else { Issue.record("not enough"); return }
        #expect(suggestions[0].confidence > suggestions[1].confidence)
    }

    @Test func recordingAPIPersistsCorrection() async {
        let store = CategoryCorrectionStore()
        let api = RecordingCategorizationAPI(
            inner: LocalStubCategorizationAPI(),
            store: store
        )
        let correction = CategoryCorrection(
            transactionId: "tx-1",
            originalGuess: "Other",
            acceptedLabel: "Dining",
            merchantName: "Some Bistro"
        )
        await api.recordCorrection(correction)
        let snapshot = await store.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.transactionId == "tx-1")
        #expect(snapshot.first?.acceptedLabel == "Dining")
    }

    @Test func recordingAPIForwardsCategorize() async {
        let api = RecordingCategorizationAPI(
            inner: LocalStubCategorizationAPI(),
            store: CategoryCorrectionStore()
        )
        let tx = makeTx(name: "AMAZON")
        let guess = await api.categorize(tx)
        #expect(guess.label == "Shopping")
    }
}
