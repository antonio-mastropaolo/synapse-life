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

    // 2026-05-18 refresh: moved off the flat gray-black palette to a
    // teal-tinted three-tier hierarchy (content / sidebar / elevated)
    // that pairs with the new app-icon gradient. The brand accent
    // shifts toward the warmer hub-amber so the icon glyph and the
    // in-app brand chip read as the same hue.
    public static let shell = Shell(
        // ~#0A1620 — deep teal-tinted near-black. Reads as the room
        // floor, not pure void. The blue undertone differentiates the
        // app from generic "dev console dark" and gives the warm
        // accent more visual snap.
        contentBackground:   ColorToken(0.040, 0.085, 0.125),

        // ~#13202C — sidebar sits ~0.05 luminance above the content.
        // Matches the top of the app-icon gradient.
        sidebarBackground:   ColorToken(0.075, 0.125, 0.170),

        // Near-white for body text; cooler dimmed secondary so it
        // recedes into the teal base rather than clashing.
        foregroundPrimary:   ColorToken(0.94, 0.95, 0.97),
        foregroundSecondary: ColorToken(0.58, 0.66, 0.74),

        // Brand accent matched to the icon hub (#FFB038 → 1.0, 0.69,
        // 0.22). Clears 4.5:1 on both surfaces, doesn't bleed into
        // the gain-green finance accent.
        brandAccent:         ColorToken(1.000, 0.690, 0.220),

        // Active-row tint with a hint of the hub-amber bleed so the
        // selected sidebar row pulls the eye like a low-energy glow
        // rather than a flat gray block.
        activeRowBackground: ColorToken(0.135, 0.180, 0.225),

        // Subtle separator — same hairline alpha, neutral hue so it
        // doesn't compete with the colored tints around it.
        separator:           ColorToken(1.0, 1.0, 1.0, opacity: 0.09),

        // Search field one notch above the sidebar, slightly cooler
        // so the input affordance reads at idle without painting a
        // hard border.
        searchFieldFill:     ColorToken(0.110, 0.165, 0.215),

        // Transaction-count badge. Stays neutral so the categorical
        // pill colors don't have to compete with it.
        badgeFill:           ColorToken(1.0, 1.0, 1.0, opacity: 0.11),
        badgeForeground:     ColorToken(0.88, 0.91, 0.94)
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

/// Deterministic mapping from a category id to its chip color.
///
/// CANONICAL SOURCE OF TRUTH: `Features.CategoryID.displayColor` in
/// `packages/SynnapseKit/Sources/Features/Categories/CategoryID.swift`.
/// The hex values here mirror that exact palette so DesignSystem-only
/// consumers (the Copilot chrome, charts, legend renderers) can read
/// the same color without crossing the DesignSystem → Features
/// dependency edge.
///
/// Reconciled 2026-05-17 during the four-branch Copilot integration:
/// agent 1's initial muted-pastel sketch was overwritten with agent
/// 3's accessibility-cleared palette so all three surfaces (Copilot
/// chrome, Dashboard pills, Categories pills) share one color.
///
/// If you change a hex here, change it in `CategoryID.displayColor`
/// and `TokenSet.category(_:)` too — the three surfaces must stay in
/// lockstep. There is no automatic check today; treat the trio as one
/// edit unit.
public enum CategoryPalette {

    public static func color(for id: CategoryId) -> ColorToken {
        switch id {
        case .restaurants:   return ColorToken(0x4C / 255.0, 0xAF / 255.0, 0x6B / 255.0) // #4CAF6B
        case .subscriptions: return ColorToken(0xA0 / 255.0, 0x6C / 255.0, 0xD5 / 255.0) // #A06CD5
        case .groceries:     return ColorToken(0x7C / 255.0, 0xB3 / 255.0, 0x42 / 255.0) // #7CB342
        case .loans:         return ColorToken(0xE5 / 255.0, 0x39 / 255.0, 0x35 / 255.0) // #E53935
        case .clothing:      return ColorToken(0xEC / 255.0, 0x40 / 255.0, 0x7A / 255.0) // #EC407A
        case .income:        return ColorToken(0x26 / 255.0, 0xA6 / 255.0, 0x9A / 255.0) // #26A69A
        case .transfers:     return ColorToken(0x42 / 255.0, 0xA5 / 255.0, 0xF5 / 255.0) // #42A5F5
        case .fees:          return ColorToken(0x8D / 255.0, 0x6E / 255.0, 0x63 / 255.0) // #8D6E63
        case .entertainment: return ColorToken(0xFF / 255.0, 0xA7 / 255.0, 0x26 / 255.0) // #FFA726
        case .personalCare:  return ColorToken(0xFF / 255.0, 0xB7 / 255.0, 0x4D / 255.0) // #FFB74D
        case .other:         return ColorToken(0x78 / 255.0, 0x90 / 255.0, 0x9C / 255.0) // #78909C
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
