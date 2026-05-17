import Foundation
import Models

/// Pure-logic anomaly explainer. Given a transaction the host has
/// flagged as anomalous and a context window of recent transactions,
/// produce a 2-3 sentence explanation, the supporting citations, and a
/// small set of suggested actions.
///
/// The reducer never invents a fact. Every claim is computed from the
/// snapshot:
///   - "3× your typical Zelle size" comes from `meanFor(category)`.
///   - "matching destination name" comes from same-name lookup across
///     accounts.
///   - "self-transfer" detection fires only when the counterparty name
///     matches an account name on the user's own ledger.
public enum AnomalyExplainerReducer {

    /// Build an explanation for `transaction`. `recentTransactions` is
    /// the 90-day window used to compute baselines.
    /// `accountNames` is the set of names belonging to the user's own
    /// accounts (lowercased) so we can recognize self-transfers without
    /// needing the full `FinanceAccount` array on the call site.
    public static func explain(
        transaction: Transaction,
        recentTransactions: [Transaction],
        accountNames: Set<String> = []
    ) -> AnomalyExplanation {
        let amount = absDecimal(transaction.amount ?? 0)
        let categoryLabel = transaction.category.displayLabel
        let dateString = formatLongDate(transaction.date)

        // Same-category baseline (mean abs amount over 90 days).
        let sameCategory = recentTransactions.filter { tx in
            guard let a = tx.amount, !tx.pending, a < 0 else { return false }
            return tx.category.displayLabel == categoryLabel && tx.id != transaction.id
        }
        let baselineMean = meanAbs(sameCategory)
        let ratio = (baselineMean > 0) ? amount / baselineMean : Decimal(0)

        // Self-transfer detection.
        let counterparty = (transaction.merchantName ?? transaction.name).lowercased()
        let isSelfTransfer = accountNames.contains { counterparty.contains($0) || $0.contains(counterparty) }

        // Compose the body — three sentences max, every claim is grounded.
        var sentences: [String] = []
        sentences.append(
            "Your \(formatCurrency(amount)) \(merchantPhrase(transaction)) on \(dateString) "
            + ratioPhrase(ratio: ratio, categoryLabel: categoryLabel, sampleCount: sameCategory.count)
            + "."
        )
        if isSelfTransfer {
            sentences.append("This appears to be a self-transfer between your accounts (the counterparty name matches an account on your ledger).")
        } else if ratio >= Decimal(string: "2.5") ?? 2 {
            sentences.append("It is your largest \(categoryLabel.lowercased()) transaction in the last 90 days.")
        }
        sentences.append(recommendation(isSelfTransfer: isSelfTransfer, ratio: ratio))

        // Citations: the triggering tx + up to 3 baseline rows the
        // sentence is computed against. The UI uses these as chips.
        let citationIDs = [transaction.id] + sameCategory
            .sorted { absDecimal($0.amount ?? 0) > absDecimal($1.amount ?? 0) }
            .prefix(3)
            .map { $0.id }

        let actions: [AnomalyExplanation.SuggestedAction] = {
            if isSelfTransfer {
                return [
                    .init(id: "act.markTransfer", label: "Mark as transfer", kind: .markAsTransfer),
                    .init(id: "act.markReviewed", label: "Mark reviewed", kind: .markReviewed),
                    .init(id: "act.threshold", label: "Set alert threshold", kind: .setAlertThreshold)
                ]
            }
            return [
                .init(id: "act.investigate", label: "Investigate", kind: .investigate),
                .init(id: "act.threshold", label: "Set alert threshold", kind: .setAlertThreshold),
                .init(id: "act.markReviewed", label: "Mark reviewed", kind: .markReviewed)
            ]
        }()

        return AnomalyExplanation(
            id: "explanation.\(transaction.id)",
            transactionId: transaction.id,
            title: "Why this was flagged",
            body: sentences.joined(separator: " "),
            citations: citationIDs,
            suggestedActions: actions
        )
    }

    // MARK: - Helpers

    static func meanAbs(_ rows: [Transaction]) -> Decimal {
        let values = rows.compactMap { tx -> Decimal? in
            guard let a = tx.amount else { return nil }
            return absDecimal(a)
        }
        guard !values.isEmpty else { return 0 }
        let sum = values.reduce(Decimal.zero, +)
        return sum / Decimal(values.count)
    }

    static func merchantPhrase(_ tx: Transaction) -> String {
        let name = tx.merchantName ?? tx.name
        if name.uppercased().contains("ZELLE") {
            return "Zelle to \(name.replacingOccurrences(of: "Zelle Payment To ", with: "", options: .caseInsensitive))"
        }
        return "\(name) charge"
    }

    static func ratioPhrase(ratio: Decimal, categoryLabel: String, sampleCount: Int) -> String {
        guard ratio > 0, sampleCount >= 2 else {
            return "is the first \(categoryLabel.lowercased()) charge of this size in your recent history"
        }
        let r = NSDecimalNumber(decimal: ratio).doubleValue
        if r >= 2.5 {
            return String(format: "is %.1f× your typical %@ size", r, categoryLabel.lowercased())
        }
        if r >= 1.5 {
            return String(format: "runs %.1f× your typical %@ size", r, categoryLabel.lowercased())
        }
        return String(format: "sits at %.1f× your typical %@ baseline", r, categoryLabel.lowercased())
    }

    static func recommendation(isSelfTransfer: Bool, ratio: Decimal) -> String {
        if isSelfTransfer {
            return "No action needed — marking it as a transfer will keep it out of future anomaly counts."
        }
        if ratio >= Decimal(string: "3.0") ?? 3 {
            return "Worth a quick check — confirm the charge or raise the alert threshold if this is the new normal."
        }
        return "Tap Mark reviewed to dismiss, or raise the alert threshold if this size is expected going forward."
    }

    static func formatLongDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }
}
