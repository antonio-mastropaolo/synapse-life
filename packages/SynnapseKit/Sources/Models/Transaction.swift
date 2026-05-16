import Foundation

/// One ledger row, projected from `/api/finance/transactions/route.ts`. The
/// route already flips Plaid's sign convention (`-amount` = outflow for the
/// UI), so the native client takes the sign as-given and preserves it.
public struct Transaction: Sendable, Hashable, Identifiable {
    public let id: String
    public let accountId: String?
    public let accountName: String?
    /// Signed amount: negative = debit (outflow), positive = credit (inflow).
    public let amount: Decimal?
    public let currency: String
    public let date: Date
    public let name: String
    public let merchantName: String?
    public let category: TransactionCategory
    public let subcategory: String?
    public let pending: Bool

    public init(
        id: String,
        accountId: String?,
        accountName: String?,
        amount: Decimal?,
        currency: String,
        date: Date,
        name: String,
        merchantName: String?,
        category: TransactionCategory,
        subcategory: String?,
        pending: Bool
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.amount = amount
        self.currency = currency
        self.date = date
        self.name = name
        self.merchantName = merchantName
        self.category = category
        self.subcategory = subcategory
        self.pending = pending
    }
}

/// Forward-compat category type. Known categories ride along as the raw
/// server string so we don't have to enumerate every Plaid bucket in code;
/// an absent or unrecognized category falls through to `.unknown` and the
/// UI shows a generic chip.
public enum TransactionCategory: Sendable, Hashable, Codable {
    case knownCategory(String)
    case unknown

    public var displayLabel: String {
        switch self {
        case .knownCategory(let s): return s
        case .unknown: return "Uncategorized"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), !s.isEmpty {
            self = .knownCategory(s)
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .knownCategory(let s): try c.encode(s)
        case .unknown: try c.encodeNil()
        }
    }
}

// MARK: - Wire shape

public struct ServerTransactionRow: Sendable {
    public let id: String
    public let source: String?
    public let accountId: String?
    public let accountName: String?
    public let amount: Double?
    public let currency: String
    public let date: Date
    public let name: String
    public let merchantName: String?
    public let category: String?
    public let subcategory: String?
    public let pending: Bool
}

extension ServerTransactionRow: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, source, accountId, accountName, amount, currency
        case date, name, merchantName, category, subcategory, pending
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.source = try c.decodeIfPresent(String.self, forKey: .source)
        self.accountId = try c.decodeIfPresent(String.self, forKey: .accountId)
        self.accountName = try c.decodeIfPresent(String.self, forKey: .accountName)
        self.amount = try c.decodeIfPresent(Double.self, forKey: .amount)
        self.currency = (try c.decodeIfPresent(String.self, forKey: .currency)) ?? "USD"
        self.date = try Self.decodeDate(from: c, key: .date)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.merchantName = try c.decodeIfPresent(String.self, forKey: .merchantName)
        self.category = try c.decodeIfPresent(String.self, forKey: .category)
        self.subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        self.pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
    }

    /// The route emits ISO `YYYY-MM-DD` strings. The per-account legacy
    /// endpoint and future `transaction_at` columns emit unix seconds.
    /// Accept both so the decoder doesn't have to fork on shape.
    private static func decodeDate(
        from c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date {
        if let s = try? c.decode(String.self, forKey: key) {
            if let d = isoDayFormatter.date(from: s) { return d }
            if let d = ISO8601DateFormatter().date(from: s) { return d }
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c, debugDescription: "unparseable date string \(s)"
            )
        }
        if let n = try? c.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: n)
        }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: c, debugDescription: "date is neither string nor number"
        )
    }
}

private let isoDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

public struct TransactionsResponse: Decodable, Sendable {
    public let rows: [Transaction]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey { case rows, nextCursor }

    public init(rows: [Transaction], nextCursor: String?) {
        self.rows = rows
        self.nextCursor = nextCursor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let serverRows = try c.decode([ServerTransactionRow].self, forKey: .rows)
        self.rows = serverRows.map(Transaction.fromServerRow)
        self.nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

extension Transaction {
    public static func fromServerRow(_ row: ServerTransactionRow) -> Transaction {
        let cat: TransactionCategory
        if let s = row.category, !s.isEmpty {
            cat = .knownCategory(s)
        } else {
            cat = .unknown
        }
        return Transaction(
            id: row.id,
            accountId: row.accountId,
            accountName: row.accountName,
            amount: decimal(from: row.amount),
            currency: row.currency.uppercased(),
            date: row.date,
            name: row.name,
            merchantName: row.merchantName,
            category: cat,
            subcategory: row.subcategory,
            pending: row.pending
        )
    }
}
