import Foundation
import Models
import Networking

/// One categorization decision: the proposed label plus a 0..1
/// confidence the UI paints as the strength of the underline beneath
/// the label.
public struct CategoryGuess: Sendable, Hashable, Codable {
    public let label: String
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = max(0, min(1, confidence))
    }
}

/// Categorization surface — turns a transaction description into a
/// short, human-readable category. The local stub uses a small ordered
/// table of regex matchers (the same buckets the synapse-v2 server
/// uses), so the UI never has to render a transaction with no chip.
public protocol CategorizationAPI: Sendable {
    func categorize(_ transaction: Transaction) async -> CategoryGuess
}

public struct LiveCategorizationAPI: CategorizationAPI {
    private let serverContractLive: Bool
    private let fallback: LocalStubCategorizationAPI

    public init(client: APIClient, serverContractLive: Bool = false) {
        self.serverContractLive = serverContractLive
        self.fallback = LocalStubCategorizationAPI()
    }

    public func categorize(_ transaction: Transaction) async -> CategoryGuess {
        guard serverContractLive else {
            return await fallback.categorize(transaction)
        }
        // When the server route lands, swap this out. Until then the
        // local stub is authoritative.
        return await fallback.categorize(transaction)
    }
}

/// Local-only categorizer. The matchers are pure regex over the
/// transaction description; order matters because the first match wins.
public struct LocalStubCategorizationAPI: CategorizationAPI {
    public init() {}

    public func categorize(_ transaction: Transaction) async -> CategoryGuess {
        return Self.classify(name: transaction.name, fallback: transaction.category.displayLabel)
    }

    /// Pure synchronous classifier. Public for the unit test suite.
    public static func classify(name: String, fallback: String = "Other") -> CategoryGuess {
        let n = name.uppercased()
        for matcher in matchers {
            if matcher.pattern.firstMatch(
                in: n,
                options: [],
                range: NSRange(n.startIndex..., in: n)
            ) != nil {
                return CategoryGuess(label: matcher.label, confidence: matcher.confidence)
            }
        }
        // Server-provided category, if any, beats "Other".
        let label = fallback.isEmpty || fallback == "Uncategorized" ? "Other" : fallback
        return CategoryGuess(label: label, confidence: 0.3)
    }

    // [label, regex, confidence] table. Order = priority. Confidence is
    // a felt value: longer/more-specific matchers carry more confidence.
    private struct Matcher: Sendable {
        let label: String
        let pattern: NSRegularExpression
        let confidence: Double
    }

    private static let matchers: [Matcher] = {
        let raw: [(String, String, Double)] = [
            ("Transfers",      "\\b(ZELLE|VENMO|CASH ?APP|WIRE|ACH|TRANSFER)\\b",   0.95),
            ("Loans",          "\\b(AFFIRM|KLARNA|AFTERPAY|SOFI LOAN|STUDENT LOAN)\\b", 0.92),
            ("Income",         "\\b(PAYROLL|DIRECT DEP|SALARY|REFUND|REIMB)\\b",       0.9),
            ("Fees",           "\\b(FEE|INTEREST|OVERDRAFT|SERVICE CHARGE)\\b",        0.9),
            ("Shopping",       "\\b(AMAZON|APPLE\\.COM|TARGET|WALMART|BESTBUY|ETSY)\\b", 0.88),
            ("Entertainment",  "\\b(NETFLIX|SPOTIFY|HULU|DISNEY|HBO|STEAM|XBOX)\\b",  0.88),
            ("Personal Care",  "\\b(CVS|WALGREENS|SEPHORA|SALON|BARBER|GYM)\\b",      0.8),
            ("Groceries",      "\\b(WHOLE FOODS|TRADER JOE|KROGER|SAFEWAY|ALDI)\\b",  0.88),
            ("Dining",         "\\b(STARBUCKS|CHIPOTLE|MCDONALD|UBER ?EATS|DOORDASH|GRUBHUB)\\b", 0.88),
            ("Transport",      "\\b(UBER|LYFT|SHELL|EXXON|CHEVRON|BP|PARKING)\\b",    0.85)
        ]
        return raw.compactMap { (label, pattern, confidence) in
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else {
                return nil
            }
            return Matcher(label: label, pattern: re, confidence: confidence)
        }
    }()
}
