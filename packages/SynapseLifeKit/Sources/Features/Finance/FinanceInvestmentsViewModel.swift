import Foundation
import Observation
import Models

public enum FinanceInvestmentsState: Sendable, Equatable {
    case idle
    case loading
    case results([InvestmentPosition])
    case empty
    case error(String)
}

@MainActor
@Observable
public final class FinanceInvestmentsViewModel {
    public private(set) var state: FinanceInvestmentsState = .idle
    public private(set) var positions: [InvestmentPosition] = []

    private let api: FinanceAPI
    private let repository: FinanceRepository

    public init(api: FinanceAPI) {
        self.api = api
        self.repository = FinanceRepository(api: api)
    }

    public func refresh() async {
        state = .loading
        do {
            try await repository.refreshInvestments()
            self.positions = await repository.investments
            state = positions.isEmpty ? .empty : .results(positions)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// Total portfolio value across all accounts (Decimal, exact).
    public var portfolioValue: Decimal {
        positions.reduce(Decimal.zero) { $0 + $1.value }
    }

    /// Sum of unrealized P&L where present. Positions with nil cost basis
    /// are skipped, matching how the route handles missing cost data.
    public var unrealizedPnL: Decimal {
        positions.reduce(Decimal.zero) { acc, p in acc + (p.unrealizedPnL ?? .zero) }
    }

    /// Allocation by SecurityKind for the donut. Returns a stable order
    /// driven by the enum's declaration.
    public func allocationByKind() -> [InvestmentAllocationSlice] {
        var totals: [SecurityKind: Decimal] = [:]
        for p in positions {
            totals[p.kind, default: .zero] += p.value
        }
        let absSum = totals.values.reduce(Decimal.zero) { $0 + abs($1) }
        guard absSum > .zero else { return [] }
        return SecurityKind.allCases.compactMap { kind -> InvestmentAllocationSlice? in
            guard let value = totals[kind] else { return nil }
            let pct = (abs(value) * Decimal(100)) / absSum
            return InvestmentAllocationSlice(kind: kind, value: value, percentage: pct)
        }
    }

    public func injectForSnapshots(positions: [InvestmentPosition]) {
        self.positions = positions
        self.state = positions.isEmpty ? .empty : .results(positions)
    }
}

public struct InvestmentAllocationSlice: Sendable, Hashable, Identifiable {
    public var id: SecurityKind { kind }
    public let kind: SecurityKind
    public let value: Decimal
    public let percentage: Decimal
}
