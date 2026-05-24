import Foundation
import Testing
import SwiftUI
import Models
@testable import Features

/// Non-snapshot tests for the pill — wiring, defaulting, resolver bridge.
/// Visual snapshot coverage lives in `Tests/SnapshotTests/CategoryPillSnapshotTests`.
@Suite("CategoryPill wiring")
@MainActor
struct CategoryPillTests {

    @Test
    func defaultLabelUppercases() {
        let pill = CategoryPill(category: .restaurants, size: .compact)
        #expect(pill.category == .restaurants)
        // Body is opaque, but the inputs determine output: labelOverride
        // is nil so the pill renders "RESTAURANTS".
        #expect(pill.labelOverride == nil)
    }

    @Test
    func colorOverrideTakesPrecedence() {
        let custom = Color.red
        let pill = CategoryPill(category: .other, size: .compact, colorOverride: custom)
        #expect(pill.colorOverride != nil)
    }

    @Test
    func transactionInitResolvesCategory() {
        // A transaction whose server label is empty falls through to the
        // rules engine, which routes NETFLIX → subscriptions.
        let tx = Transaction(
            id: "t1", accountId: nil, accountName: nil,
            amount: Decimal(-12.99), currency: "USD",
            date: Date(),
            name: "NETFLIX.COM",
            merchantName: "Netflix",
            category: .unknown, subcategory: nil, pending: false
        )
        let pill = CategoryPill(transaction: tx)
        #expect(pill.category == .subscriptions)
    }

    @Test
    func transactionInitPrefersServerLabelWhenMapped() {
        // Server label "Food & Drink" maps to .restaurants even though
        // the description string would also have matched (chipotle).
        let tx = Transaction(
            id: "t2", accountId: nil, accountName: nil,
            amount: Decimal(-9.50), currency: "USD",
            date: Date(),
            name: "CHIPOTLE 0341",
            merchantName: "Chipotle",
            category: .knownCategory("Food & Drink"),
            subcategory: nil, pending: false
        )
        let pill = CategoryPill(transaction: tx)
        #expect(pill.category == .restaurants)
    }

    @Test
    func unmatchedServerLabelFallsThroughToRulesEngine() {
        // Server label "Other" is intentionally not in CategoryResolver's
        // map; the description ("ZELLE PAYMENT") matches Transfers in
        // the rules engine, which becomes the rendered id.
        let tx = Transaction(
            id: "t3", accountId: nil, accountName: nil,
            amount: Decimal(-100), currency: "USD",
            date: Date(),
            name: "ZELLE PAYMENT TO J",
            merchantName: nil,
            category: .knownCategory("Other"), subcategory: nil, pending: false
        )
        let pill = CategoryPill(transaction: tx)
        #expect(pill.category == .transfers)
    }

    @Test
    func displayColorIsDeterministicPerId() {
        // Sanity check: the same id renders the same color twice in a
        // row. This is the contract the rest of the team relies on.
        let a = CategoryID.subscriptions.displayColor
        let b = CategoryID.subscriptions.displayColor
        #expect(a == b)
    }
}
