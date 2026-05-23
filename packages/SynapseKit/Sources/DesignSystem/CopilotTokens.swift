import Foundation
import SwiftUI

/// Palette and category tokens for the Copilot-shaped macOS shell.
///
/// Split from [[Tokens]] so the Copilot redesign owns its own value
/// surface: a deliberate copy of Copilot's chrome (deep near-black
/// sidebar slightly lighter than the content area, soft warm gold as
/// the brand accent, muted desaturated category pills).
///
/// The chrome was refreshed toward the current Apple-system dark look:
/// the teal-tinted void gave way to a refined neutral graphite that sits
/// flush with the CockpitInstrument content identity, so chrome and
/// content read as one cohesive surface. The warm gold brand accent
/// stays — it is the app's icon-derived brand mark and the one warm note
/// in an otherwise neutral, restrained dark shell.
///
/// The category tokens live here, not on `TokenSet`, because they are
/// per-category — Tokens carries one accent per identity, whereas the
/// Copilot shell needs eleven simultaneously. A flat lookup keeps the
/// call sites short (`CategoryPalette.color(for: .restaurants)`).
public enum CopilotTokens {

    /// The chrome tokens — sidebar / content / accents the live shell
    /// paints against. These are tuned by eye; the invariants the suite
    /// locks are (a) dark by design, (b) sidebar slightly lighter than
    /// content, (c) brand-accent >= 3.0:1 vs both surfaces, (d) active-row
    /// tint distinct from the sidebar.
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
        // Refined neutral graphite. Matches the CockpitInstrument
        // background so the content pane and the shell chrome are one
        // continuous surface rather than two tinted panels.
        contentBackground:   ColorToken(0.055, 0.058, 0.066),

        // Sidebar sits a touch above the content. The small luminance
        // delta is what lets the eye read the two regions as adjacent
        // panes under the same light.
        sidebarBackground:   ColorToken(0.105, 0.110, 0.122),

        // Near-white body text; a neutral dimmed secondary that recedes
        // into the graphite base instead of carrying a color cast.
        foregroundPrimary:   ColorToken(0.95, 0.96, 0.97),
        foregroundSecondary: ColorToken(0.64, 0.66, 0.71),

        // Warm gold brand accent, the icon-derived brand mark. The one
        // warm note in the shell; clears 4.5:1 on both surfaces and stays
        // clear of the cockpit gain-green.
        brandAccent:         ColorToken(1.000, 0.710, 0.250),

        // Active-row tint lifts the selected row a clear step above the
        // sidebar so it reads as a soft raised panel.
        activeRowBackground: ColorToken(0.185, 0.190, 0.205),

        // Hairline separator — present but never a hard line.
        separator:           ColorToken(1.0, 1.0, 1.0, opacity: 0.10),

        // Search field one notch above the sidebar so the input
        // affordance reads at idle without a painted border.
        searchFieldFill:     ColorToken(0.150, 0.155, 0.168),

        // Transaction-count badge. Stays neutral so the categorical
        // pill colors do not have to compete with it.
        badgeFill:           ColorToken(1.0, 1.0, 1.0, opacity: 0.12),
        badgeForeground:     ColorToken(0.90, 0.92, 0.95)
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
/// `packages/SynapseKit/Sources/Features/Categories/CategoryID.swift`.
/// The hex values here mirror that exact palette so DesignSystem-only
/// consumers (the Copilot chrome, charts, legend renderers) can read
/// the same color without crossing the DesignSystem -> Features
/// dependency edge.
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
    /// that want to iterate the palette.
    public static let knownCategories: [CategoryId] = [
        .restaurants, .subscriptions, .groceries, .loans,
        .clothing, .income, .transfers, .fees,
        .entertainment, .personalCare, .other
    ]
}
