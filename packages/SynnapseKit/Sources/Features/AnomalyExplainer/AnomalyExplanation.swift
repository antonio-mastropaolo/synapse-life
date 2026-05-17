import Foundation
import Models

/// One AI-authored explanation for an anomaly card. The `body` is 2-3
/// sentences in the voice of the assistant, citing the transaction +
/// the user's baseline. `citations` are the `Transaction.id`s the
/// explanation references; the UI renders them as tappable chips.
/// `suggestedActions` are the bottom-row chips (Mark as transfer,
/// Investigate, Set alert threshold...).
public struct AnomalyExplanation: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    /// The triggering transaction.
    public let transactionId: String
    public let title: String
    public let body: String
    public let citations: [String]
    public let suggestedActions: [SuggestedAction]

    public init(
        id: String,
        transactionId: String,
        title: String,
        body: String,
        citations: [String],
        suggestedActions: [SuggestedAction]
    ) {
        self.id = id
        self.transactionId = transactionId
        self.title = title
        self.body = body
        self.citations = citations
        self.suggestedActions = suggestedActions
    }

    public struct SuggestedAction: Sendable, Hashable, Codable, Identifiable {
        public let id: String
        public let label: String
        public let kind: Kind

        public init(id: String, label: String, kind: Kind) {
            self.id = id
            self.label = label
            self.kind = kind
        }

        public enum Kind: String, Sendable, Hashable, Codable {
            case markAsTransfer
            case investigate
            case setAlertThreshold
            case markReviewed
            case ignore
        }
    }
}
