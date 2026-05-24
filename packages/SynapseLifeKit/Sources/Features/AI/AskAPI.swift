import Foundation
import Models
import Networking

/// Streaming free-text Ask surface. Drives the command bar's NL query
/// result card. Each yielded `AskDelta` is one token (or one logical
/// chunk) of the assistant's reply.
public enum AskDelta: Sendable, Hashable {
    case text(String)
    case done
    case error(String)
}

public struct AskContext: Sendable {
    public let accounts: [FinanceAccount]
    public let recentTransactions: [Transaction]

    public init(accounts: [FinanceAccount], recentTransactions: [Transaction]) {
        self.accounts = accounts
        self.recentTransactions = recentTransactions
    }
}

public protocol AskAPI: Sendable {
    func ask(question: String, context: AskContext) -> AsyncThrowingStream<AskDelta, Error>
}

/// Live implementation. Defers to local stub until the route lands.
public struct LiveAskAPI: AskAPI {
    private let serverContractLive: Bool
    private let fallback: LocalStubAskAPI

    public init(client: APIClient, serverContractLive: Bool = false) {
        self.serverContractLive = serverContractLive
        self.fallback = LocalStubAskAPI()
    }

    public func ask(
        question: String,
        context: AskContext
    ) -> AsyncThrowingStream<AskDelta, Error> {
        return fallback.ask(question: question, context: context)
    }
}

/// Local stub: structured answer composed from the user's actual
/// snapshot. Never says "endpoint not implemented" — instead computes a
/// useful sentence from accounts + recent transactions.
public struct LocalStubAskAPI: AskAPI {
    private let interTokenDelay: UInt64

    /// `interTokenDelay` paces the per-token emission so the streaming UI
    /// has a visible cadence in production. Tests pass `0` to remove the
    /// timing dependency entirely.
    public init(interTokenDelayNanos: UInt64 = 18_000_000) {
        self.interTokenDelay = interTokenDelayNanos
    }

    public func ask(
        question: String,
        context: AskContext
    ) -> AsyncThrowingStream<AskDelta, Error> {
        let answer = Self.composeAnswer(question: question, context: context)
        let delay = interTokenDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                for word in answer.split(separator: " ", omittingEmptySubsequences: false) {
                    if Task.isCancelled { break }
                    continuation.yield(.text(String(word) + " "))
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                }
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Compose a structured answer. Public so the unit tests can lock
    /// the exact wording without spinning a stream.
    public static func composeAnswer(question: String, context: AskContext) -> String {
        let q = question.lowercased()
        if q.contains("net worth") || q.contains("how much") && q.contains("worth") {
            let net = netWorth(context.accounts)
            return "Your current net worth is \(formatCurrency(net)) across \(context.accounts.count) accounts."
        }
        if q.contains("spend") || q.contains("spent") {
            let total = recentSpend(context.recentTransactions)
            return "You spent \(formatCurrency(total)) in the last 30 days across \(context.recentTransactions.count) transactions."
        }
        if q.contains("largest") || q.contains("biggest") {
            if let row = largestOutflow(context.recentTransactions) {
                let absAmount = absDecimal(row.amount ?? 0)
                return "Your largest recent outflow was \(row.name) for \(formatCurrency(absAmount)) on \(formatShortDate(row.date))."
            }
        }
        if q.contains("checking") || q.contains("balance") {
            if let acct = context.accounts.first(where: { $0.kind == .checking }),
               let bal = acct.currentBalance {
                return "Your checking account \(acct.name) currently shows \(formatCurrency(bal))."
            }
        }
        // Default: echo + a snapshot summary so the user always sees
        // something grounded.
        let net = netWorth(context.accounts)
        return "I'll need more context for \"\(question)\". For reference, your net worth is \(formatCurrency(net))."
    }

    private static func netWorth(_ accounts: [FinanceAccount]) -> Decimal {
        let assets = accounts
            .filter { !$0.kind.isLiability }
            .compactMap { $0.currentBalance }
            .reduce(Decimal.zero, +)
        let liabilities = accounts
            .filter { $0.kind.isLiability }
            .compactMap { $0.currentBalance }
            .reduce(Decimal.zero, +)
        return assets - liabilities
    }

    private static func recentSpend(_ rows: [Transaction]) -> Decimal {
        return rows
            .compactMap { tx -> Decimal? in
                guard let a = tx.amount, !tx.pending, a < 0 else { return nil }
                return -a
            }
            .reduce(Decimal.zero, +)
    }

    private static func largestOutflow(_ rows: [Transaction]) -> Transaction? {
        return rows
            .filter { tx in
                guard let a = tx.amount, !tx.pending else { return false }
                return a < 0
            }
            .max { absDecimal($0.amount ?? 0) < absDecimal($1.amount ?? 0) }
    }
}
