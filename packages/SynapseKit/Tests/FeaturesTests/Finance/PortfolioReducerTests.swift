import Foundation
import Testing
@testable import Models
@testable import Features

private func account(
    id: String, kind: AccountKind, balance: Decimal, currency: String = "USD"
) -> FinanceAccount {
    FinanceAccount(
        id: id, institutionId: nil, institutionName: nil,
        name: id, officialName: nil, mask: nil,
        kind: kind, currency: currency,
        currentBalance: balance, availableBalance: nil, limitAmount: nil,
        balanceCapturedAt: nil
    )
}

/// Pure-functions tests. The reducer must not touch I/O or capture global
/// state; the snapshots below also act as a contract for the
/// FinancePersonalViewModel which calls into it.
@Suite("PortfolioReducer")
struct PortfolioReducerTests {

    @Test
    func netWorthSumsAssetsMinusLiabilities() throws {
        let accounts: [FinanceAccount] = [
            account(id: "cash", kind: .checking, balance: Decimal(1_000)),
            account(id: "savings", kind: .savings, balance: Decimal(5_000)),
            account(id: "brk", kind: .brokerage, balance: Decimal(20_000)),
            account(id: "cc", kind: .credit, balance: Decimal(1_500)),
            account(id: "loan", kind: .loan, balance: Decimal(8_000))
        ]
        let net = try PortfolioReducer.netWorth(accounts)
        // assets = 1000 + 5000 + 20000 = 26000
        // liabilities = 1500 + 8000 = 9500
        // net = 16500
        #expect(net == Decimal(16_500))
    }

    @Test
    func emptyAccountsReturnsZeroNetWorth() throws {
        #expect(try PortfolioReducer.netWorth([]) == Decimal.zero)
    }

    @Test
    func allocationSlicesSumToOneHundred() throws {
        let accounts: [FinanceAccount] = [
            account(id: "cash", kind: .checking, balance: Decimal(2_000)),
            account(id: "brk", kind: .brokerage, balance: Decimal(8_000))
        ]
        let slices = try PortfolioReducer.allocation(accounts)
        #expect(slices.count == 2)
        let total = slices.reduce(Decimal.zero) { $0 + $1.percentage }
        // Tolerance is for Decimal rounding when redistributing the last %.
        let diff = abs(total - Decimal(100))
        #expect(diff < Decimal(string: "0.01")!)
    }

    @Test
    func allocationEmptyInputReturnsEmpty() throws {
        let slices = try PortfolioReducer.allocation([])
        #expect(slices.isEmpty)
    }

    @Test
    func allocationGroupsByKind() throws {
        let accounts: [FinanceAccount] = [
            account(id: "c1", kind: .checking, balance: Decimal(1_000)),
            account(id: "c2", kind: .checking, balance: Decimal(1_000)),
            account(id: "b1", kind: .brokerage, balance: Decimal(2_000))
        ]
        let slices = try PortfolioReducer.allocation(accounts)
        // Two checking accounts merge into one slice.
        #expect(slices.count == 2)
        let checking = try #require(slices.first { $0.kind == .checking })
        #expect(checking.amount == Decimal(2_000))
    }

    @Test
    func mixedCurrenciesThrowsWithoutFxRates() {
        let accounts: [FinanceAccount] = [
            account(id: "usd", kind: .checking, balance: Decimal(100), currency: "USD"),
            account(id: "eur", kind: .checking, balance: Decimal(100), currency: "EUR")
        ]
        #expect(throws: PortfolioReducerError.self) {
            _ = try PortfolioReducer.netWorth(accounts)
        }
    }

    @Test
    func mixedCurrenciesAcceptsExplicitFxRates() throws {
        let accounts: [FinanceAccount] = [
            account(id: "usd", kind: .checking, balance: Decimal(100), currency: "USD"),
            account(id: "eur", kind: .checking, balance: Decimal(100), currency: "EUR")
        ]
        // 1 EUR = 1.10 USD → 100 USD + 100*1.10 USD = 210 USD
        let fx: [String: Decimal] = ["EUR": Decimal(string: "1.10")!]
        let net = try PortfolioReducer.netWorth(accounts, baseCurrency: "USD", fxRates: fx)
        #expect(net == Decimal(210))
    }
}
