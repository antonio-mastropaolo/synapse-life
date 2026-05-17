import SwiftUI

/// Canonical category palette — mirrors `CategoryID.displayColor` in
/// `Features/Categories/CategoryID.swift`. Kept here as a `TokenSet`
/// helper so non-Features callers (charts, instruments, the LIFE
/// shell, the Copilot chrome) can read the same color without crossing
/// module boundaries.
///
/// `Features.CategoryID` is the source of truth at the data layer;
/// this surface re-publishes the exact same hex values onto `TokenSet`
/// so a future identity (high-contrast, print, color-blind variants)
/// can override the palette without touching the Features layer.
/// Added 2026-05-17 during the four-branch Copilot integration to
/// reconcile three different palettes onto one.
extension TokenSet {

    /// The eleven canonical category slugs — string raw values match
    /// `CategoryID.slug` so a server-side category label can round-trip
    /// through both surfaces.
    public enum CategoryPaletteID: String, Sendable, Hashable, CaseIterable {
        case restaurants
        case subscriptions
        case groceries
        case loans
        case clothing
        case income
        case transfers
        case personalCare = "personal-care"
        case entertainment
        case fees
        case other
    }

    /// Resolve a canonical category id to its display color. WCAG AA
    /// against the dark Copilot chrome at all sizes; the values are
    /// the same as `Features.CategoryID.displayColor` and should stay
    /// in sync. If you change one, change both — the test target's
    /// `CategoryPalette` parity check locks them.
    public func category(_ id: CategoryPaletteID) -> Color {
        switch id {
        case .restaurants:
            return Color(red: 0x4C / 255.0, green: 0xAF / 255.0, blue: 0x6B / 255.0)
        case .subscriptions:
            return Color(red: 0xA0 / 255.0, green: 0x6C / 255.0, blue: 0xD5 / 255.0)
        case .groceries:
            return Color(red: 0x7C / 255.0, green: 0xB3 / 255.0, blue: 0x42 / 255.0)
        case .loans:
            return Color(red: 0xE5 / 255.0, green: 0x39 / 255.0, blue: 0x35 / 255.0)
        case .clothing:
            return Color(red: 0xEC / 255.0, green: 0x40 / 255.0, blue: 0x7A / 255.0)
        case .income:
            return Color(red: 0x26 / 255.0, green: 0xA6 / 255.0, blue: 0x9A / 255.0)
        case .transfers:
            return Color(red: 0x42 / 255.0, green: 0xA5 / 255.0, blue: 0xF5 / 255.0)
        case .personalCare:
            return Color(red: 0xFF / 255.0, green: 0xB7 / 255.0, blue: 0x4D / 255.0)
        case .entertainment:
            return Color(red: 0xFF / 255.0, green: 0xA7 / 255.0, blue: 0x26 / 255.0)
        case .fees:
            return Color(red: 0x8D / 255.0, green: 0x6E / 255.0, blue: 0x63 / 255.0)
        case .other:
            return Color(red: 0x78 / 255.0, green: 0x90 / 255.0, blue: 0x9C / 255.0)
        }
    }
}
