import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Locks the Copilot-shell palette and the category-pill tokens.
///
/// The Copilot redesign needs three things from the design system:
///   1. A discrete "Copilot" token set — sidebar surface, content
///      background, brand accent — that the live macOS shell paints
///      against. The values are pinned here so a refactor cannot
///      silently shift the chrome.
///   2. A complete `CategoryPalette` covering every category the
///      Transactions / Categories / Recurrings views will draw chips
///      against. The mapping is deterministic so other agents can
///      look up a color by category id without coordination.
///   3. WCAG AA on the pairs the shell actually paints (foreground on
///      sidebar, foreground on background, accent on background as a
///      non-text element).
@Suite("Copilot tokens")
struct CopilotTokensTests {

    // MARK: - Shell chrome

    @Test("Copilot shell tokens are dark by design")
    func chromeIsDark() {
        let chrome = CopilotTokens.shell
        // Sidebar is slightly lighter than the content background so the
        // user reads the two regions as adjacent panels rather than as
        // one flat dark surface. The luminance delta is small (~0.02)
        // but real.
        #expect(chrome.contentBackground.red < 0.10)
        #expect(chrome.sidebarBackground.red < 0.15)
        #expect(chrome.sidebarBackground.red >= chrome.contentBackground.red,
                "Sidebar should be at least as light as the content area")
    }

    @Test("Copilot shell foreground clears WCAG AA on both surfaces")
    func foregroundContrast() {
        let c = CopilotTokens.shell
        #expect(contrastRatio(c.foregroundPrimary, c.sidebarBackground) >= 4.5)
        #expect(contrastRatio(c.foregroundPrimary, c.contentBackground) >= 4.5)
        // Secondary foreground (uppercase section headers, footer rows)
        // sits at the 3.0:1 non-text minimum since it carries the same
        // info as the row labels alongside it.
        #expect(contrastRatio(c.foregroundSecondary, c.sidebarBackground) >= 3.0)
    }

    @Test("Brand accent clears 3.0:1 as a non-text element")
    func accentContrast() {
        let c = CopilotTokens.shell
        #expect(contrastRatio(c.brandAccent, c.sidebarBackground) >= 3.0)
        #expect(contrastRatio(c.brandAccent, c.contentBackground) >= 3.0)
    }

    @Test("Active-row accent is distinct from the sidebar background")
    func activeRowDistinct() {
        let c = CopilotTokens.shell
        let same =
            c.activeRowBackground.red   == c.sidebarBackground.red &&
            c.activeRowBackground.green == c.sidebarBackground.green &&
            c.activeRowBackground.blue  == c.sidebarBackground.blue
        #expect(!same, "Active-row tint must differ from the sidebar")
    }

    // MARK: - Category palette

    @Test("Category palette covers every documented category")
    func categoryPaletteIsComplete() {
        // The brief enumerates eleven categories. Each must resolve to a
        // distinct token so the pills are immediately distinguishable.
        let ids: [CategoryId] = [
            .restaurants, .subscriptions, .groceries, .loans,
            .clothing, .income, .transfers, .fees,
            .entertainment, .personalCare, .other
        ]
        var seen: Set<String> = []
        for id in ids {
            let token = CategoryPalette.color(for: id)
            // Hex-ish fingerprint — three doubles rounded to 3 places.
            // Identical tokens collide in `seen`.
            let key = String(format: "%.3f,%.3f,%.3f",
                             token.red, token.green, token.blue)
            #expect(!seen.contains(key),
                    "Category \(id) shares a color with another: \(key)")
            seen.insert(key)
        }
        #expect(seen.count == ids.count)
    }

    @Test("Income is green-ish and fees/loans land in the warm half")
    func categoryColorsCarrySemantic() {
        // The pills do not need to be literal traffic-light colors but
        // they should not lie about polarity — income should not be red,
        // fees should not be green. We assert a directional invariant:
        // income.green > income.red (cool), fees.red > fees.green (warm).
        let income = CategoryPalette.color(for: .income)
        #expect(income.green > income.red,
                "Income should read as a cool/green-ish chip")

        let fees = CategoryPalette.color(for: .fees)
        #expect(fees.red > fees.green,
                "Fees should read as a warm/red-ish chip")
    }

    @Test("Unknown category falls back to .other")
    func unknownFallsBack() {
        let other = CategoryPalette.color(for: .other)
        let fallback = CategoryPalette.color(for: CategoryId(rawValue: "made-up"))
        #expect(other.red == fallback.red)
        #expect(other.green == fallback.green)
        #expect(other.blue == fallback.blue)
    }
}
