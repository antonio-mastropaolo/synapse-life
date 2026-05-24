import Foundation
import Models
import Persistence

/// Maps `LLMToolCall` names onto the local SwiftData stores and returns
/// the result as a JSON string the model can ingest in its next turn.
///
/// `get_accounts`, `get_transactions(start, end, category?)`, and
/// `get_recurrings` are wired to their backing stores. `get_recurrings`
/// requires a `RecurringStore`; when one isn't supplied it throws
/// `LLMError.toolNotImplemented` so the router degrades gracefully rather
/// than crashing. `get_investments` is registered as a tool descriptor but
/// still throws `LLMError.toolNotImplemented`.
public actor ToolCallRegistry {
    private let accountStore: AccountStore
    private let transactionStore: TransactionStore
    private let investmentStore: InvestmentStore
    private let recurringStore: RecurringStore?

    public init(
        accountStore: AccountStore,
        transactionStore: TransactionStore,
        investmentStore: InvestmentStore,
        recurringStore: RecurringStore? = nil
    ) {
        self.accountStore = accountStore
        self.transactionStore = transactionStore
        self.investmentStore = investmentStore
        self.recurringStore = recurringStore
    }

    /// Default tool descriptors exposed to the model. The four-tool set
    /// is fixed for Phase 3; argument schemas are kept narrow to make
    /// model output easy to validate.
    public static func defaultTools() -> [LLMTool] {
        [
            LLMTool(
                name: "get_accounts",
                description: "Return the user's accounts as a JSON array. No arguments.",
                argsSchemaJSON: #"{"type":"object","properties":{}}"#
            ),
            LLMTool(
                name: "get_transactions",
                description: "Return transactions between two ISO dates, optionally filtered by category.",
                argsSchemaJSON: #"""
                {"type":"object","properties":{"start":{"type":"string","description":"ISO date YYYY-MM-DD"},"end":{"type":"string","description":"ISO date YYYY-MM-DD, exclusive"},"category":{"type":"string"}},"required":["start","end"]}
                """#
            ),
            LLMTool(
                name: "get_investments",
                description: "Return the user's investment positions as a JSON array. No arguments.",
                argsSchemaJSON: #"{"type":"object","properties":{}}"#
            ),
            LLMTool(
                name: "get_recurrings",
                description: "Return the user's recurring transactions. No arguments. (Phase 3 — pending store wire-up.)",
                argsSchemaJSON: #"{"type":"object","properties":{}}"#
            )
        ]
    }

    /// Dispatch a tool call by name, returning the JSON-encoded result.
    public func dispatch(
        _ name: String,
        args: [String: String]
    ) async throws -> String {
        switch name {
        case "get_accounts":
            return try await encodeAccounts()
        case "get_transactions":
            return try await encodeTransactions(args: args)
        case "get_investments":
            throw LLMError.toolNotImplemented("get_investments")
        case "get_recurrings":
            return try await encodeRecurrings()
        default:
            throw LLMError.toolNotImplemented(name)
        }
    }

    // MARK: - Encoders

    private func encodeAccounts() async throws -> String {
        let accounts = try await accountStore.all()
        let rows = accounts.map { acct -> [String: Any] in
            var row: [String: Any] = [
                "id": acct.id,
                "name": acct.name,
                "kind": acct.kind.rawValue,
                "currency": acct.currency
            ]
            if let bal = acct.currentBalance {
                row["currentBalance"] = NSDecimalNumber(decimal: bal).doubleValue
            }
            if let inst = acct.institutionName { row["institutionName"] = inst }
            if let mask = acct.mask { row["mask"] = mask }
            return row
        }
        return try Self.jsonString(["accounts": rows])
    }

    private func encodeTransactions(args: [String: String]) async throws -> String {
        guard let startStr = args["start"], let endStr = args["end"] else {
            throw LLMError.toolNotImplemented("get_transactions:missing start/end")
        }
        guard let start = Self.parseISODate(startStr),
              let end = Self.parseISODate(endStr) else {
            throw LLMError.toolNotImplemented("get_transactions:bad date")
        }
        let category = args["category"]
        let rows = try await transactionStore.between(start, and: end, category: category)
        let encoded = rows.map { tx -> [String: Any] in
            var row: [String: Any] = [
                "id": tx.id,
                "date": Self.isoDayString(tx.date),
                "name": tx.name,
                "currency": tx.currency,
                "pending": tx.pending,
                "category": tx.category.displayLabel
            ]
            if let amount = tx.amount {
                row["amount"] = NSDecimalNumber(decimal: amount).doubleValue
            }
            if let aid = tx.accountId { row["accountId"] = aid }
            if let an = tx.accountName { row["accountName"] = an }
            if let m = tx.merchantName { row["merchantName"] = m }
            return row
        }
        return try Self.jsonString(["transactions": encoded, "count": encoded.count])
    }

    private func encodeRecurrings() async throws -> String {
        guard let recurringStore else {
            throw LLMError.toolNotImplemented("get_recurrings")
        }
        let rows = try await recurringStore.all()
        let encoded = rows.map { r -> [String: Any] in
            [
                "id": r.id,
                "merchant": r.merchant,
                "category": r.category,
                "medianAmount": NSDecimalNumber(decimal: r.medianAmount).doubleValue,
                "cadenceDays": r.cadenceDays,
                "lastSeen": Self.isoDayString(r.lastSeen),
                "predictedNext": Self.isoDayString(r.predictedNext),
                "occurrenceCount": r.occurrenceCount,
                "confidence": r.confidence,
                "isIncome": r.isIncome
            ]
        }
        return try Self.jsonString(["recurrings": encoded, "count": encoded.count])
    }

    private static func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys]
        )
        guard let s = String(data: data, encoding: .utf8) else {
            throw LLMError.decoding
        }
        return s
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseISODate(_ s: String) -> Date? {
        isoDayFormatter.date(from: s)
    }

    private static func isoDayString(_ d: Date) -> String {
        isoDayFormatter.string(from: d)
    }
}
