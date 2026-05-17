import Foundation
import Testing
@testable import Models
@testable import Features

private let fixedToday: Date = {
    var c = DateComponents()
    c.calendar = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")
    c.year = 2026; c.month = 5; c.day = 17
    c.hour = 12; c.minute = 0
    return c.date!
}()

private func charges(
    merchant: String,
    category: String,
    count: Int,
    cadenceDays: Int,
    lastDaysAgo: Int,
    amount: Decimal,
    amountJitter: Decimal = 0
) -> [Transaction] {
    var out: [Transaction] = []
    for i in 0..<count {
        let daysAgo = lastDaysAgo + (count - 1 - i) * cadenceDays
        let date = fixedToday.addingTimeInterval(-Double(daysAgo) * 86_400)
        let signed = -(amount + (amountJitter * Decimal(i) - amountJitter * Decimal(count - 1) / 2))
        out.append(Transaction(
            id: "\(merchant.lowercased())-\(i)",
            accountId: "acct-1", accountName: "T",
            amount: signed,
            currency: "USD", date: date,
            name: merchant, merchantName: merchant,
            category: .knownCategory(category),
            subcategory: nil, pending: false
        ))
    }
    return out
}

@Suite("SubscriptionDetector")
struct SubscriptionDetectorTests {

    @Test("stable monthly subscription is detected")
    func stableMonthly() {
        let txs = charges(
            merchant: "NETFLIX",
            category: "SUBSCRIPTIONS",
            count: 6, cadenceDays: 30, lastDaysAgo: 4,
            amount: 23
        )
        let result = SubscriptionDetector.detectSubscriptions(
            transactions: txs, today: fixedToday
        )
        #expect(result.count == 1)
        let s = result[0]
        #expect(s.merchant == "NETFLIX")
        #expect(s.cadenceDays == 30)
        #expect(s.monthlyEquivalent == Decimal(23))
        #expect(s.cadenceLabel == "Monthly")
    }

    @Test("noisy-amount monthly is rejected (Affirm)")
    func noisyAmountRejected() {
        // Affirm-style: monthly cadence but amount swings $25 each
        // month. Rejected because amount is not stable.
        let txs = charges(
            merchant: "AFFIRM PAYMENTS",
            category: "LOANS",
            count: 6, cadenceDays: 30, lastDaysAgo: 5,
            amount: 80, amountJitter: 30
        )
        let result = SubscriptionDetector.detectSubscriptions(
            transactions: txs, today: fixedToday
        )
        #expect(result.isEmpty)
    }

    @Test("weekly cadence is rejected — not a subscription cadence")
    func weeklyCadenceRejected() {
        let txs = charges(
            merchant: "TRASH SERVICE",
            category: "SUBSCRIPTIONS",
            count: 6, cadenceDays: 7, lastDaysAgo: 1,
            amount: 10.00
        )
        let result = SubscriptionDetector.detectSubscriptions(
            transactions: txs, today: fixedToday
        )
        // Recurring? Yes. Subscription? No — cadence ≠ {30, 90, 365}.
        #expect(result.isEmpty)
    }

    @Test("merchant-category fallback: Netflix mis-categorized as Entertainment")
    func merchantTokenFallback() {
        let txs = charges(
            merchant: "NETFLIX.COM",
            category: "ENTERTAINMENT",  // server lies
            count: 5, cadenceDays: 30, lastDaysAgo: 2,
            amount: 22.99
        )
        let result = SubscriptionDetector.detectSubscriptions(
            transactions: txs, today: fixedToday
        )
        // Fallback recognizes NETFLIX as a subscription merchant
        // despite the wrong server category. Display form is
        // title-cased ("Netflix") because the bank's raw string
        // ("NETFLIX.COM") differs from the normalized key.
        #expect(result.count == 1)
        #expect(result[0].merchant == "Netflix")
        #expect(result[0].category == .subscriptions)
    }

    @Test("quarterly cadence: monthlyEquivalent = amount / 3")
    func quarterlyNormalization() {
        // 3 charges at 90d cadence, ending today: 0, 90, 180 days
        // ago — all inside the 180-day window.
        let txs = charges(
            merchant: "ADOBE CREATIVE",
            category: "SUBSCRIPTIONS",
            count: 3, cadenceDays: 90, lastDaysAgo: 0,
            amount: 150.00
        )
        let result = SubscriptionDetector.detectSubscriptions(
            transactions: txs, today: fixedToday
        )
        #expect(result.count == 1)
        #expect(result[0].monthlyEquivalent == Decimal(50))
        #expect(result[0].cadenceLabel == "Quarterly")
    }

    @Test("monthly total sums every subscription")
    func monthlyTotalSums() {
        // Use whole-dollar amounts so the test asserts exact Decimal
        // equality without bumping into Decimal-from-Double precision.
        let netflix = charges(
            merchant: "NETFLIX",
            category: "SUBSCRIPTIONS",
            count: 4, cadenceDays: 30, lastDaysAgo: 3, amount: 23
        )
        let spotify = charges(
            merchant: "SPOTIFY",
            category: "SUBSCRIPTIONS",
            count: 4, cadenceDays: 30, lastDaysAgo: 5, amount: 17
        )
        let icloud = charges(
            merchant: "APPLE.COM",
            category: "SUBSCRIPTIONS",
            count: 4, cadenceDays: 30, lastDaysAgo: 1, amount: 10
        )
        let txs = netflix + spotify + icloud
        let result = SubscriptionDetector.detectSubscriptions(
            transactions: txs, today: fixedToday
        )
        #expect(result.count == 3)
        let total = SubscriptionDetector.monthlyTotal(result)
        #expect(total == Decimal(50))
    }

    @Test("output sorted by monthlyEquivalent descending")
    func sortedByCost() {
        let icloud = charges(
            merchant: "APPLE.COM",
            category: "SUBSCRIPTIONS",
            count: 4, cadenceDays: 30, lastDaysAgo: 1, amount: 10
        )
        let netflix = charges(
            merchant: "NETFLIX",
            category: "SUBSCRIPTIONS",
            count: 4, cadenceDays: 30, lastDaysAgo: 1, amount: 23
        )
        let result = SubscriptionDetector.detectSubscriptions(
            transactions: icloud + netflix, today: fixedToday
        )
        #expect(result.count == 2)
        #expect(result[0].merchant == "NETFLIX")   // higher cost first
        #expect(result[1].merchant == "Apple")     // title-cased fallback
    }
}
