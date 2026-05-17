import Foundation
import SwiftUI

/// Palette and category tokens for the Copilot-shaped macOS shell.
///
/// Split from [[Tokens]] so the Copilot redesign owns its own value
/// surface: a deliberate copy of Copilot's chrome (deep-near-black
/// sidebar slightly lighter than the content area, soft warm yellow as
/// the brand accent, muted desaturated category pills) anchored to the
/// reference screenshot at `/tmp/copilot-ref/01-default.png`.
///
/// The category tokens live here, not on `TokenSet`, because they are
/// per-category — Tokens carries one accent per identity, whereas the
/// Copilot shell needs eleven simultaneously. A flat lookup keeps the
/// call sites short (`CategoryPalette.color(for: .restaurants)`).
public enum CopilotTokens {

    /// The chrome tokens — sidebar / content / accents the live shell
    /// paints against. These are tuned by eye against the reference; the
    /// invariants the suite locks are (a) dark by design, (b) sidebar
    /// slightly lighter than content, (c) brand-accent ≥3.0:1 vs both
    /// surfaces, (d) active-row tint distinct from the sidebar.
    public struct Shell: Sendable, Equatable {
        public let contentBackground:  ColorToken
        public let sidebarBackground:  ColorToken
        public let foregroundPrimary:  ColorToken
        public let foregroundSecondary: ColorToken
        public let brandAccent:        ColorToken
        public let activeRowBackground: ColorToken
        public let separator:          ColorToken
        public let searchFieldFill:    ColorToken
        public let badgeFill:          ColorToken
        public let badgeForeground:    ColorToken
    }

    public static let shell = Shell(
        // ~#0E0E10 — slightly warmer than pure black so the eye reads it
        // as a panel, not a void. Sits beneath the content surfaces.
        contentBackground:   ColorToken(0.055, 0.055, 0.063),

        // ~#17171A — about ~0.04 luminance brighter than the content so
        // the sidebar reads as the foreground panel without flipping
        // the polarity that makes dark mode comfortable.
        sidebarBackground:   ColorToken(0.090, 0.090, 0.100),

        // Near-white for body text, dimmed for section headers/footer.
        foregroundPrimary:   ColorToken(0.92, 0.92, 0.94),
        foregroundSecondary: ColorToken(0.62, 0.62, 0.68),

        // Copilot's brand mark reads as a warm muted yellow. We pick a
        // value that clears 3.0:1 on both surfaces and does not bleed
        // toward the gain-green of the finance accent.
        brandAccent:         ColorToken(0.95, 0.78, 0.30),

        // Subtle tint behind the active row. Sits at ~0.06 luminance
        // above the sidebar so the eye picks the row out without the
        // background overpowering the label.
        activeRowBackground: ColorToken(0.145, 0.145, 0.160),

        // 1pt rules between the sidebar and the content area, plus the
        // footer separator. Reads as a hairline at every viewing
        // distance because the sRGB delta is intentionally small.
        separator:           ColorToken(1.0, 1.0, 1.0, opacity: 0.08),

        // Search field fill — one step lighter than the sidebar so the
        // input affordance reads even at idle.
        searchFieldFill:     ColorToken(0.130, 0.130, 0.145),

        // Transactions badge fill ("3204" in the reference). A muted
        // off-white pill against the dark sidebar; we paint the count
        // in the same primary fg so the contrast is the same as the
        // row label.
        badgeFill:           ColorToken(1.0, 1.0, 1.0, opacity: 0.10),
        badgeForeground:     ColorToken(0.85, 0.85, 0.88)
    )
}

// MARK: - Category palette

/// A category identifier for the Categories / Recurrings / Transactions
/// surfaces that consume the palette below. We carry the value as a
/// `RawRepresentable` string so other agents can map server-side
/// category labels to a known token without a switch.
public struct CategoryId: Sendable, Equatable, Hashable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public extension CategoryId {
    static let restaurants   = CategoryId(rawValue: "restaurants")
    static let subscriptions = CategoryId(rawValue: "subscriptions")
    static let groceries     = CategoryId(rawValue: "groceries")
    static let loans         = CategoryId(rawValue: "loans")
    static let clothing      = CategoryId(rawValue: "clothing")
    static let income        = CategoryId(rawValue: "income")
    static let transfers     = CategoryId(rawValue: "transfers")
    static let fees          = CategoryId(rawValue: "fees")
    static let entertainment = CategoryId(rawValue: "entertainment")
    static let personalCare  = CategoryId(rawValue: "personal-care")
    static let other         = CategoryId(rawValue: "other")
}

/// Deterministic mapping from a category id to its chip color. The
/// palette is tuned to match Copilot's muted-pastel feel: every chip
/// reads as quiet against the dark shell while still being immediately
/// distinguishable from its neighbors. Unknown ids fall back to
/// `.other` so a server-side schema drift does not crash the chip
/// renderer.
public enum CategoryPalette {

    public static func color(for id: CategoryId) -> ColorToken {
        switch id {
        case .restaurants:   return ColorToken(0.95, 0.55, 0.42) // warm coral
        case .subscriptions: return ColorToken(0.62, 0.55, 0.95) // soft violet
        case .groceries:     return ColorToken(0.56, 0.82, 0.50) // sage green
        case .loans:         return ColorToken(0.92, 0.62, 0.30) // amber
        case .clothing:      return ColorToken(0.85, 0.58, 0.78) // dusty pink
        case .income:        return ColorToken(0.36, 0.82, 0.62) // mint
        case .transfers:     return ColorToken(0.55, 0.72, 0.92) // sky blue
        case .fees:          return ColorToken(0.90, 0.40, 0.40) // muted red
        case .entertainment: return ColorToken(0.78, 0.58, 0.92) // lilac
        case .personalCare:  return ColorToken(0.92, 0.70, 0.85) // blush
        case .other:         return ColorToken(0.62, 0.62, 0.66) // neutral
        default:             return Self.color(for: .other)
        }
    }

    /// Stable list of every known category. Useful for legend renderers
    /// (agent 3 / agent 4) that want to iterate the palette.
    public static let knownCategories: [CategoryId] = [
        .restaurants, .subscriptions, .groceries, .loans,
        .clothing, .income, .transfers, .fees,
        .entertainment, .personalCare, .other
    ]
}
