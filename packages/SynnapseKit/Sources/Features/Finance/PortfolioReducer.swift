import Foundation
import Models

/// A single slice of the allocation donut. `percentage` is in 0...100.
public struct AllocationSlice: Sendable, Hashable, Identifiable {
    public var id: AccountKind { kind }
    public let kind: AccountKind
    public let amount: Decimal
    public let percentage: Decimal

    public init(kind: AccountKind, amount: Decimal, percentage: Decimal) {
        self.kind = kind
        self.amount = amount
        self.percentage = percentage
    }
}

public enum PortfolioReducerError: Error, Sendable, Equatable {
    case mixedCurrenciesWithoutFxRates(currencies: [String])
    case missingFxRate(String)
}

/// Pure reducer over a list of accounts. No I/O, no global state, all
/// transformations are deterministic. The view model is the only thing
/// allowed to call into the reducer; the snapshot tests cover every branch.
public enum PortfolioReducer {

    /// Sum assets minus liabilities. When the account list contains more
    /// than one currency, the caller must provide explicit fx rates against
    /// the base currency — we never silently coerce.
    public static func netWorth(
        _ accounts: [FinanceAccount],
        baseCurrency: String = "USD",
        fxRates: [String: Decimal] = [:]
    ) throws -> Decimal {
        try requireCurrencyCoverage(accounts, base: baseCurrency, fxRates: fxRates)
        return accounts.reduce(Decimal.zero) { running, account in
            guard let raw = account.currentBalance else { return running }
            let inBase = convert(raw, from: account.currency,
                                 to: baseCurrency, fxRates: fxRates)
            let signed: Decimal = account.kind.isLiability ? -inBase : inBase
            return running + signed
        }
    }

    /// Build a list of `AllocationSlice` from absolute balances, grouped by
    /// `AccountKind`. Liabilities collapse to negative slices — the caller
    /// chooses whether to display them. Percentages are computed against
    /// the absolute total and sum to ~100 (within rounding).
    public static func allocation(
        _ accounts: [FinanceAccount],
        baseCurrency: String = "USD",
        fxRates: [String: Decimal] = [:]
    ) throws -> [AllocationSlice] {
        guard !accounts.isEmpty else { return [] }
        try requireCurrencyCoverage(accounts, base: baseCurrency, fxRates: fxRates)
        var totals: [AccountKind: Decimal] = [:]
        for account in accounts {
            guard let raw = account.currentBalance else { continue }
            let inBase = convert(raw, from: account.currency,
                                 to: baseCurrency, fxRates: fxRates)
            totals[account.kind, default: .zero] += inBase
        }
        let absoluteSum = totals.values.reduce(Decimal.zero) { $0 + abs($1) }
        guard absoluteSum > .zero else { return [] }
        // Sort by AccountKind enum order for deterministic output.
        let ordered = AccountKind.allCases.compactMap { kind -> AllocationSlice? in
            guard let value = totals[kind] else { return nil }
            let pct = (abs(value) * Decimal(100)) / absoluteSum
            return AllocationSlice(kind: kind, amount: value, percentage: pct)
        }
        return ordered
    }

    // MARK: - Private

    private static func requireCurrencyCoverage(
        _ accounts: [FinanceAccount],
        base: String,
        fxRates: [String: Decimal]
    ) throws {
        var missing: [String] = []
        var foreign: Set<String> = []
        for account in accounts {
            if account.currency == base { continue }
            foreign.insert(account.currency)
            if fxRates[account.currency] == nil {
                missing.append(account.currency)
            }
        }
        if foreign.isEmpty { return }
        if !missing.isEmpty {
            // If any fx rate is missing, signal which currencies are involved.
            throw PortfolioReducerError.mixedCurrenciesWithoutFxRates(
                currencies: Array(foreign).sorted()
            )
        }
    }

    private static func convert(
        _ amount: Decimal,
        from currency: String,
        to base: String,
        fxRates: [String: Decimal]
    ) -> Decimal {
        if currency == base { return amount }
        let rate = fxRates[currency] ?? Decimal(1)
        return amount * rate
    }
}
