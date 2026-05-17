import Foundation
import Models

/// One citation chip the Ask bar paints below the streamed answer.
/// The `targetId` carries either a transaction ID or an account ID
/// depending on `kind`; the host uses it to route on tap.
public struct AskCitation: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let kind: Kind
    public let targetId: String
    public let label: String

    public init(id: String, kind: Kind, targetId: String, label: String) {
        self.id = id
        self.kind = kind
        self.targetId = targetId
        self.label = label
    }

    public enum Kind: String, Sendable, Hashable, Codable {
        case transaction
        case account
        case category
        case insight
    }
}

/// Pure-logic extractor: given a question and a context window, pick
/// the citations the streaming answer should attach. The reducer
/// matches on intent in the question (largest? checking? dining?) and
/// references the matching rows by ID. Same approach as the existing
/// `LocalStubAskAPI.composeAnswer` so the citations align with the
/// prose.
public enum AskCitationsExtractor {

    public static func extract(question: String, context: AskContext) -> [AskCitation] {
        let q = question.lowercased()
        var out: [AskCitation] = []

        if q.contains("largest") || q.contains("biggest") {
            let outflows = context.recentTransactions
                .filter { tx in
                    guard let a = tx.amount, !tx.pending else { return false }
                    return a < 0
                }
                .sorted { absDecimal($0.amount ?? 0) > absDecimal($1.amount ?? 0) }
                .prefix(3)
            for tx in outflows {
                out.append(AskCitation(
                    id: "cite.tx.\(tx.id)",
                    kind: .transaction,
                    targetId: tx.id,
                    label: tx.name
                ))
            }
            return out
        }

        if q.contains("checking") || q.contains("balance") {
            if let acct = context.accounts.first(where: { $0.kind == .checking }) {
                out.append(AskCitation(
                    id: "cite.acct.\(acct.id)",
                    kind: .account,
                    targetId: acct.id,
                    label: acct.name
                ))
            }
            return out
        }

        // Category-scoped questions: "how much did I spend on X".
        if q.contains("spend") || q.contains("spent") {
            // Cite top 3 outflows so the answer can ground its number.
            let outflows = context.recentTransactions
                .filter { tx in
                    guard let a = tx.amount, !tx.pending else { return false }
                    return a < 0
                }
                .sorted { absDecimal($0.amount ?? 0) > absDecimal($1.amount ?? 0) }
                .prefix(3)
            for tx in outflows {
                out.append(AskCitation(
                    id: "cite.tx.\(tx.id)",
                    kind: .transaction,
                    targetId: tx.id,
                    label: tx.name
                ))
            }
            return out
        }

        return out
    }
}
