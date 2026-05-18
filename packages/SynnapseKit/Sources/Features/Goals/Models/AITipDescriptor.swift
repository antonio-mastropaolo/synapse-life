import Foundation

/// Small DTO bridging an AI signal tile to `GoalsStore.applyAITip`.
/// The tile constructs one of these inline — it doesn't need to know
/// about Goal/GoalTarget/GoalKind. The store decides how to convert
/// the descriptor into a fully-shaped `Goal` based on the suggested
/// kind + parsed target amount.
public struct AITipDescriptor: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let detailText: String
    public let icon: String
    public let suggestedKind: GoalKind
    public let categoryHint: String?
    public let parsedTargetAmount: Decimal?

    public init(
        id: UUID = UUID(),
        title: String,
        detailText: String,
        icon: String,
        suggestedKind: GoalKind,
        categoryHint: String? = nil,
        parsedTargetAmount: Decimal? = nil
    ) {
        self.id = id
        self.title = title
        self.detailText = detailText
        self.icon = icon
        self.suggestedKind = suggestedKind
        self.categoryHint = categoryHint
        self.parsedTargetAmount = parsedTargetAmount
    }

    /// Extracts the first `$NNN` or `$NNN.NN` amount from a string.
    /// Used by the AI tile to construct a descriptor without doubling
    /// the regex in every call site.
    public static func parseAmount(from text: String) -> Decimal? {
        let pattern = #"\$([\d,]+(?:\.\d{2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        let clean = text[r].replacingOccurrences(of: ",", with: "")
        return Decimal(string: clean)
    }
}
