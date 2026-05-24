import Foundation
import Models

/// Deterministic in-memory `PlaidConnector` used by previews, unit tests,
/// and the demo "no real institutions linked" path. The shape of every
/// returned value matches Plaid sandbox to keep the seam honest — only the
/// values are fixed.
public actor StubPlaidConnector: PlaidConnector {

    // Single, fixed clock so the deterministic fixtures don't depend on
    // wall-clock time. Callers that need a moving clock can pass one in.
    private let now: Date
    private var cursorCounter: Int = 0

    /// `now` defaults to a fixed epoch so two test runs produce byte-equal
    /// fixtures. Production callers (previews, demo seed) can leave it.
    public init(now: Date = Date(timeIntervalSince1970: 1_730_000_000)) {
        self.now = now
    }

    public func createLinkToken(userId: String) async throws -> PlaidLinkToken {
        // Plaid's real tokens last 30 min in sandbox, 4 h elsewhere. We
        // surface the longer ceiling because LivePlaidConnector will
        // honor whichever the server returns.
        let expires = now.addingTimeInterval(4 * 3600)
        return PlaidLinkToken(
            token: "link-sandbox-\(userId)-stub",
            expiration: expires
        )
    }

    public func exchangePublicToken(_ publicToken: String) async throws -> PlaidItem {
        PlaidItem(
            id: "item-stub-1",
            institutionId: "ins_109508",
            institutionName: "First Platypus Bank",
            accessTokenRef: "kc:plaid:item-stub-1"
        )
    }

    public func syncTransactions(
        itemId: String,
        cursor: String?
    ) async throws -> PlaidSyncDelta {
        cursorCounter += 1
        let nextCursor = "cursor-\(cursorCounter)"

        // First call returns three deterministic transactions; every
        // subsequent call returns an empty delta with hasMore = false.
        if cursor == nil {
            let txns = [
                makeTxn(
                    id: "txn-stub-1",
                    date: now.addingTimeInterval(-3 * 86400),
                    amount: Decimal(string: "-42.50"),
                    name: "Blue Bottle Coffee",
                    category: "FOOD_AND_DRINK"
                ),
                makeTxn(
                    id: "txn-stub-2",
                    date: now.addingTimeInterval(-2 * 86400),
                    amount: Decimal(string: "-128.93"),
                    name: "Whole Foods Market",
                    category: "GROCERIES"
                ),
                makeTxn(
                    id: "txn-stub-3",
                    date: now.addingTimeInterval(-1 * 86400),
                    amount: Decimal(string: "2500.00"),
                    name: "Payroll Deposit",
                    category: "INCOME"
                )
            ]
            return PlaidSyncDelta(
                added: txns,
                modified: [],
                removedIds: [],
                nextCursor: nextCursor,
                hasMore: false
            )
        }

        return PlaidSyncDelta(
            added: [],
            modified: [],
            removedIds: [],
            nextCursor: nextCursor,
            hasMore: false
        )
    }

    public func fetchAccounts(itemId: String) async throws -> [FinanceAccount] {
        [
            FinanceAccount(
                id: "acc-stub-checking",
                institutionId: "ins_109508",
                institutionName: "First Platypus Bank",
                name: "Plaid Checking",
                officialName: "Plaid Gold Standard 0% Interest Checking",
                mask: "0000",
                kind: .checking,
                currency: "USD",
                currentBalance: Decimal(string: "1234.56"),
                availableBalance: Decimal(string: "1200.00"),
                limitAmount: nil,
                balanceCapturedAt: now
            ),
            FinanceAccount(
                id: "acc-stub-credit",
                institutionId: "ins_109508",
                institutionName: "First Platypus Bank",
                name: "Plaid Credit Card",
                officialName: "Plaid Diamond 12.5% APR Interest Credit Card",
                mask: "3333",
                kind: .credit,
                currency: "USD",
                currentBalance: Decimal(string: "410.00"),
                availableBalance: nil,
                limitAmount: Decimal(string: "2000.00"),
                balanceCapturedAt: now
            )
        ]
    }

    public func fetchInvestments(itemId: String) async throws -> [InvestmentPosition] {
        [
            InvestmentPosition(
                securityId: "sec-aapl",
                accountId: "acc-stub-brokerage",
                accountName: "Plaid Brokerage",
                ticker: "AAPL",
                name: "Apple Inc.",
                kind: .stock,
                quantity: Decimal(string: "10")!,
                price: Decimal(string: "195.00")!,
                value: Decimal(string: "1950.00")!,
                costBasis: Decimal(string: "1500.00"),
                unrealizedPnL: Decimal(string: "450.00"),
                unrealizedPnLPct: Decimal(string: "30.0"),
                currency: "USD"
            ),
            InvestmentPosition(
                securityId: "sec-voo",
                accountId: "acc-stub-brokerage",
                accountName: "Plaid Brokerage",
                ticker: "VOO",
                name: "Vanguard S&P 500 ETF",
                kind: .etf,
                quantity: Decimal(string: "5")!,
                price: Decimal(string: "480.00")!,
                value: Decimal(string: "2400.00")!,
                costBasis: Decimal(string: "2000.00"),
                unrealizedPnL: Decimal(string: "400.00"),
                unrealizedPnLPct: Decimal(string: "20.0"),
                currency: "USD"
            )
        ]
    }

    public func removeItem(itemId: String) async throws {
        // No-op: the stub doesn't persist link state.
    }

    // MARK: - Internal helpers

    private func makeTxn(
        id: String,
        date: Date,
        amount: Decimal?,
        name: String,
        category: String
    ) -> Transaction {
        Transaction(
            id: id,
            accountId: "acc-stub-checking",
            accountName: "Plaid Checking",
            amount: amount,
            currency: "USD",
            date: date,
            name: name,
            merchantName: name,
            category: .knownCategory(category),
            subcategory: nil,
            pending: false
        )
    }
}
