import Foundation
@testable import Models
@testable import Features

/// Deterministic "now" used across the AccountDetail test files. Same
/// 2026-05-17 12:00 UTC anchor as the Recurrings tests so any shared
/// fixture line up in time.
enum AccountDetailFixtures {

    static let today: Date = {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")
        c.year = 2026; c.month = 5; c.day = 17
        c.hour = 12; c.minute = 0
        return c.date!
    }()

    /// Build a `FinanceAccount` with sensible defaults. Tests only pass
    /// the fields they care about.
    static func account(
        id: String = "acc-test",
        kind: AccountKind = .checking,
        currency: String = "USD",
        currentBalance: Decimal? = Decimal(string: "1000.00"),
        availableBalance: Decimal? = Decimal(string: "1000.00"),
        capturedDaysAgo: Int? = 2
    ) -> FinanceAccount {
        let captured = capturedDaysAgo.map {
            today.addingTimeInterval(-Double($0) * 86_400)
        }
        return FinanceAccount(
            id: id,
            institutionId: "ins_test",
            institutionName: "Test Bank",
            name: "Test Account",
            officialName: nil,
            mask: "0000",
            kind: kind,
            currency: currency,
            currentBalance: currentBalance,
            availableBalance: availableBalance,
            limitAmount: kind == .credit ? Decimal(string: "25000.00") : nil,
            balanceCapturedAt: captured
        )
    }

    /// One transaction with mostly-default decorations. Defaults to
    /// posted (not pending) so callers don't have to opt-in to the
    /// detector's "real charge" path.
    static func tx(
        id: String,
        daysAgo: Int,
        amountString: String,
        accountId: String = "acc-test",
        merchant: String = "Test Merchant",
        category: String = "Subscriptions",
        pending: Bool = false
    ) -> Transaction {
        Transaction(
            id: id,
            accountId: accountId,
            accountName: "Test Account",
            amount: Decimal(string: amountString),
            currency: "USD",
            date: today.addingTimeInterval(-Double(daysAgo) * 86_400),
            name: merchant,
            merchantName: merchant,
            category: .knownCategory(category),
            subcategory: nil,
            pending: pending
        )
    }
}
