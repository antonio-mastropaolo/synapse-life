import Foundation
import SwiftUI
import Models

/// Canonical identifier for the Copilot-style category-pill system.
///
/// `TransactionCategory` (in Models) carries the *server-supplied* category
/// string as-is — `.knownCategory("Food & Drink")`, `.knownCategory("Travel")`,
/// `.unknown`. That wire shape is forward-compat with any Plaid bucket the
/// route happens to emit and must not be enumerated.
///
/// `CategoryID` is the *display* layer: a small, fixed list of 10 visual
/// buckets (the ones a user can color-code on a pill in the UI) plus a
/// `.custom(slug)` escape hatch for user-added categories, plus `.other`
/// for anything not matched. The auto-categorizer in [[CategoryRulesEngine]]
/// maps a transaction's `name` / `merchantName` onto a `CategoryID`; the
/// renderer in [[CategoryPill]] colors the pill from that id. The server
/// string is preserved on the Transaction and shown in the detail row.
///
/// Default ids are deliberately product-flavored ("Restaurants", not
/// "FOOD_AND_DRINK") because they appear on the pill verbatim. Casing on
/// the pill is forced uppercase at render time.
public enum CategoryID: Sendable, Hashable, Codable {

    // MARK: - Default identifiers (the 10 visible in the screenshot)

    case restaurants
    case subscriptions
    case groceries
    case loans
    case clothing
    case income
    case transfers
    case personalCare
    case entertainment
    case fees

    // MARK: - Catch-all + user-defined

    /// Nothing matched a default regex and no custom rule fired.
    case other

    /// A user-added category. Slug is a stable, lowercase, kebab-cased id.
    case custom(slug: String)

    // MARK: - Display

    /// Human-readable label shown alongside the pill in the Categories
    /// surface. The pill itself uppercases this at render time.
    public var displayName: String {
        switch self {
        case .restaurants:    return "Restaurants"
        case .subscriptions:  return "Subscriptions"
        case .groceries:      return "Groceries"
        case .loans:          return "Loans"
        case .clothing:       return "Clothing"
        case .income:         return "Income"
        case .transfers:      return "Transfers"
        case .personalCare:   return "Personal Care"
        case .entertainment:  return "Entertainment"
        case .fees:           return "Fees"
        case .other:          return "Other"
        case .custom(let s):  return slugToTitle(s)
        }
    }

    /// Emoji shown to the left of the name in the Categories list. Custom
    /// categories carry their own emoji on the [[CategoryStore]] record;
    /// this value is the *default* shown until the user picks one.
    public var defaultEmoji: String {
        switch self {
        case .restaurants:    return "🍽️"
        case .subscriptions:  return "🔁"
        case .groceries:      return "🛒"
        case .loans:          return "💳"
        case .clothing:       return "👕"
        case .income:         return "💰"
        case .transfers:      return "🔀"
        case .personalCare:   return "💈"
        case .entertainment:  return "🎬"
        case .fees:           return "⚠️"
        case .other:          return "•"
        case .custom:         return "🏷️"
        }
    }

    /// Pill background color. Hex values are documented in
    /// `CATEGORIES_INTEGRATION_MANIFEST.md` so the rest of the team can
    /// pick them up from a single source. Custom categories carry their
    /// own color on the store record; this returns a neutral fallback so
    /// callers always get a renderable color.
    public var displayColor: Color {
        switch self {
        case .restaurants:    return Color(hex: 0x4CAF6B)
        case .subscriptions:  return Color(hex: 0xA06CD5)
        case .groceries:      return Color(hex: 0x7CB342)
        case .loans:          return Color(hex: 0xE53935)
        case .clothing:       return Color(hex: 0xEC407A)
        case .income:         return Color(hex: 0x26A69A)
        case .transfers:      return Color(hex: 0x42A5F5)
        case .personalCare:   return Color(hex: 0xFFB74D)
        case .entertainment:  return Color(hex: 0xFFA726)
        case .fees:           return Color(hex: 0x8D6E63)
        case .other:          return Color(hex: 0x78909C)
        case .custom:         return Color(hex: 0x78909C)
        }
    }

    /// Default 10 + `.other`, in the order the Categories surface lists
    /// them. Custom categories are appended after this list by the store.
    public static let defaults: [CategoryID] = [
        .restaurants, .subscriptions, .groceries, .loans, .clothing,
        .income, .transfers, .personalCare, .entertainment, .fees, .other,
    ]

    /// Stable slug used as a UserDefaults key and as the persisted Codable
    /// representation. Custom slugs ride through as-is.
    public var slug: String {
        switch self {
        case .restaurants:    return "restaurants"
        case .subscriptions:  return "subscriptions"
        case .groceries:      return "groceries"
        case .loans:          return "loans"
        case .clothing:       return "clothing"
        case .income:         return "income"
        case .transfers:      return "transfers"
        case .personalCare:   return "personal-care"
        case .entertainment:  return "entertainment"
        case .fees:           return "fees"
        case .other:          return "other"
        case .custom(let s):  return s
        }
    }

    /// Inverse of [[slug]]. Unknown slugs fall through to `.custom(slug)`
    /// so a forward-compat store roundtrip never loses user data.
    public static func from(slug: String) -> CategoryID {
        switch slug {
        case "restaurants":    return .restaurants
        case "subscriptions":  return .subscriptions
        case "groceries":      return .groceries
        case "loans":          return .loans
        case "clothing":       return .clothing
        case "income":         return .income
        case "transfers":      return .transfers
        case "personal-care":  return .personalCare
        case "entertainment":  return .entertainment
        case "fees":           return .fees
        case "other":          return .other
        default:               return .custom(slug: slug)
        }
    }

    // MARK: - Codable
    //
    // The slug is the on-disk representation. Encoding as a single string
    // keeps the JSON small and forward-compat with new default ids.

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        self = .from(slug: s)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(slug)
    }
}

// MARK: - Helpers

private func slugToTitle(_ slug: String) -> String {
    slug
        .split(separator: "-")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}

extension Color {
    /// 0xRRGGBB hex initializer. Lossy on round-trip via UIColor but
    /// exact on render because we control both ends — the values live in
    /// `CategoryID.displayColor` and never escape into a `ColorToken`.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
