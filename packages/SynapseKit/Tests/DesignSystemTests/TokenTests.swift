import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Design system contrast")
struct TokenTests {

    @Test("WCAG AA for default identity, light scheme")
    func defaultLightContrast() {
        let t = Tokens.defaultLight
        // Normal text on background and on surface must clear 4.5:1.
        #expect(contrastRatio(t.foregroundPrimary, t.background) >= 4.5)
        #expect(contrastRatio(t.foregroundPrimary, t.surface)    >= 4.5)
        // Accent on background can be treated as large UI element (3:1).
        #expect(contrastRatio(t.accent, t.background) >= 3.0)
    }

    @Test("WCAG AA for default identity, dark scheme")
    func defaultDarkContrast() {
        let t = Tokens.defaultDark
        #expect(contrastRatio(t.foregroundPrimary, t.background) >= 4.5)
        #expect(contrastRatio(t.foregroundPrimary, t.surface)    >= 4.5)
        #expect(contrastRatio(t.accent, t.background) >= 3.0)
    }

    @Test("Contrast ratio is symmetric")
    func symmetry() {
        let a = ColorToken(0.1, 0.1, 0.1)
        let b = ColorToken(0.9, 0.9, 0.9)
        #expect(abs(contrastRatio(a, b) - contrastRatio(b, a)) < 1e-9)
    }

    @Test("Identical colors give 1.0")
    func identical() {
        let c = ColorToken(0.5, 0.5, 0.5)
        let r = contrastRatio(c, c)
        #expect(abs(r - 1.0) < 1e-9)
    }

    @Test("Pure black / pure white = 21:1")
    func extremes() {
        let r = contrastRatio(ColorToken(0, 0, 0), ColorToken(1, 1, 1))
        #expect(abs(r - 21.0) < 1e-6)
    }
}
