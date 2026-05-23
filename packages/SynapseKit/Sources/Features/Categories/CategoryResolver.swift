import Foundation
import Models

/// Bridges the server-supplied `TransactionCategory` (free-form string)
/// to the canonical `CategoryID` used by the pill system.
///
/// The mapping is:
///   1. If the server string maps onto a known label, use that id.
///   2. Otherwise fall back to [[CategoryRulesEngine]] over the
///      transaction's `name` + `merchantName`.
///
/// This keeps the wire shape untouched (the Transaction still encodes
/// `.knownCategory("Food & Drink")`) while letting the UI pin a
/// deterministic color to every row.
public enum CategoryResolver {

    /// Map a Plaid-style server label onto the canonical id list. Returns
    /// `nil` when no direct mapping exists; callers should then defer to
    /// the rules engine on the description.
    public static func mapServerLabel(_ label: String) -> CategoryID? {
        let l = label.lowercased()
        if l.contains("food") || l.contains("drink") || l.contains("restaurant") { return .restaurants }
        if l.contains("groc") || l.contains("supermarket")                       { return .groceries }
        if l.contains("travel") || l.contains("transport")                       { return nil } // unmapped on purpose
        if l.contains("loan") || l.contains("credit card")                       { return .loans }
        if l.contains("clothing") || l.contains("apparel")                       { return .clothing }
        if l.contains("income") || l.contains("payroll") || l.contains("deposit") { return .income }
        if l.contains("transfer")                                                { return .transfers }
        if l.contains("personal care") || l.contains("gym") || l.contains("hair") { return .personalCare }
        if l.contains("entertainment") || l.contains("movie")                    { return .entertainment }
        if l.contains("fee") || l.contains("overdraft") || l.contains("interest"){ return .fees }
        if l.contains("subscription") || l.contains("software")                  { return .subscriptions }
        return nil
    }

    /// End-to-end resolver. Always returns a concrete id (worst case:
    /// `.other`). The caller can pass an optional `CategoryStore`
    /// snapshot of custom categories; resolution into customs is the
    /// caller's job (auto-rules for custom categories are out of scope
    /// for M-categories — keep this layer pure).
    public static func resolve(_ transaction: Transaction) -> CategoryID {
        if case .knownCategory(let s) = transaction.category, !s.isEmpty {
            if let mapped = mapServerLabel(s) { return mapped }
        }
        return CategoryRulesEngine.categorize(transaction)
    }
}
