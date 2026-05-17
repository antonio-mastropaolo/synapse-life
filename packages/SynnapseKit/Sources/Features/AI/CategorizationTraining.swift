import Foundation
import Models

/// One user-supplied correction. The categorizer logs these locally so
/// a future ship-back-to-server path can use them as training data.
public struct CategoryCorrection: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let transactionId: String
    public let originalGuess: String
    public let acceptedLabel: String
    public let merchantName: String
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        transactionId: String,
        originalGuess: String,
        acceptedLabel: String,
        merchantName: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.originalGuess = originalGuess
        self.acceptedLabel = acceptedLabel
        self.merchantName = merchantName
        self.timestamp = timestamp
    }
}

/// Drives the 3-bar confidence indicator. The thresholds are the felt
/// values matching the matcher confidences in
/// `LocalStubCategorizationAPI`: `high` for the regex-anchored
/// matchers, `medium` for the lower-confidence ones, `low` for the
/// "Other" fallback.
public enum ConfidenceLevel: Int, Sendable, Hashable, Codable {
    case low = 1
    case medium = 2
    case high = 3

    public static func from(confidence: Double) -> ConfidenceLevel {
        if confidence >= 0.85 { return .high }
        if confidence >= 0.6  { return .medium }
        return .low
    }
}

extension CategoryGuess {
    /// Convenience for the UI: snap the 0..1 confidence into the
    /// 3-bar indicator. Pure / deterministic so it can be tested.
    public var confidenceLevel: ConfidenceLevel {
        ConfidenceLevel.from(confidence: confidence)
    }
}

/// Extension to `CategorizationAPI` with the wider AI++ shape:
///   - `suggestions(for:)` returns the top-K candidate categories so
///     low-confidence rows can offer alternative chips.
///   - `recordCorrection(_:)` logs a user fix locally.
///
/// Default implementations let any existing conformer (Live or
/// LocalStub) pick up the AI++ behavior without having to opt in.
public protocol CategorizationTraining: CategorizationAPI {
    /// Top-K guesses for a transaction, sorted by confidence
    /// descending. The first row is the primary guess returned by
    /// `categorize(_:)`. The rest are alternative chips the UI shows
    /// on low-confidence rows.
    func suggestions(for transaction: Transaction, top: Int) async -> [CategoryGuess]

    /// Record a user correction. The default in-memory store does
    /// nothing observable; the AI++ store accumulates them so a
    /// future server route can ship them back as training pairs.
    func recordCorrection(_ correction: CategoryCorrection) async
}

/// Default in-memory corrections log. Thread-safe via an actor so
/// it's safe to share across hosts under Swift 6 strict concurrency.
public actor CategoryCorrectionStore {
    public private(set) var corrections: [CategoryCorrection] = []

    public init(initial: [CategoryCorrection] = []) {
        self.corrections = initial
    }

    public func append(_ correction: CategoryCorrection) {
        corrections.append(correction)
    }

    public func snapshot() -> [CategoryCorrection] {
        return corrections
    }

    public func clear() {
        corrections.removeAll()
    }
}

extension LocalStubCategorizationAPI: CategorizationTraining {
    /// Top-K suggestions from the matcher table. Order = matchers in
    /// the table; we pick the K with highest base confidence, then
    /// fall back to "Other" if there aren't enough matches.
    public func suggestions(for transaction: Transaction, top: Int = 3) async -> [CategoryGuess] {
        return Self.topKSuggestions(name: transaction.name, top: top)
    }

    /// No-op default. The AI++ host wires a `CategoryCorrectionStore`
    /// in front of this when it wants persistence.
    public func recordCorrection(_ correction: CategoryCorrection) async {
        // Intentionally a no-op — see `RecordingCategorizationAPI`.
    }

    /// Public so the unit suite can lock the exact list without
    /// reaching into the private matcher table.
    public static func topKSuggestions(name: String, top: Int = 3) -> [CategoryGuess] {
        let primary = classify(name: name)
        let altLabels: [String] = ["Shopping", "Dining", "Transport", "Entertainment", "Personal Care", "Groceries", "Income", "Transfers"]
        var out: [CategoryGuess] = [primary]
        for label in altLabels where label != primary.label && out.count < top {
            // Alternatives carry a damped confidence so the UI shows
            // them under the primary chip.
            out.append(CategoryGuess(label: label, confidence: max(0.2, primary.confidence - 0.4)))
        }
        return Array(out.prefix(top))
    }
}

/// Recording wrapper — forwards `categorize`/`suggestions` to the
/// underlying API and persists corrections in the store. The
/// `CommandBarViewModel` / category pill UI uses this so corrections
/// flow into a single observable place.
public struct RecordingCategorizationAPI: CategorizationTraining {
    private let inner: any CategorizationTraining
    private let store: CategoryCorrectionStore

    public init(inner: any CategorizationTraining, store: CategoryCorrectionStore) {
        self.inner = inner
        self.store = store
    }

    public func categorize(_ transaction: Transaction) async -> CategoryGuess {
        return await inner.categorize(transaction)
    }

    public func suggestions(for transaction: Transaction, top: Int = 3) async -> [CategoryGuess] {
        return await inner.suggestions(for: transaction, top: top)
    }

    public func recordCorrection(_ correction: CategoryCorrection) async {
        await store.append(correction)
    }
}
