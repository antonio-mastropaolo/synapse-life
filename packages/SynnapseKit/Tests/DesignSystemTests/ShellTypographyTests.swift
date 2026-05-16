import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Locks the Cockpit Dense shell typography contract.
///
/// The shell uses SF Mono at an 11pt base for tick rows, ledger rows, and
/// the sidebar tree. Headers fall back to SF Pro so they remain readable
/// at hierarchy levels above the dense tick rows. The DesignSystem exposes
/// two helpers — `Tokens.tickerFont(size:weight:)` and `Tokens.headerFont`
/// — so callers do not need to know about platform font registration.
@Suite("Cockpit shell typography")
struct ShellTypographyTests {

    @Test("Tick base size is 11pt")
    func tickBaseSize() {
        #expect(Tokens.tickBaseSize == 11.0)
    }

    @Test("tickerFont returns a monospaced descriptor at the requested size")
    func tickerFontIsMonospaced() {
        let f = Tokens.tickerFont(size: 11.0)
        #expect(f.isMonospaced)
        #expect(f.pointSize == 11.0)
    }

    @Test("tickerFont default size matches the shell base")
    func tickerFontDefaultsToBase() {
        let f = Tokens.tickerFont()
        #expect(f.pointSize == Tokens.tickBaseSize)
        #expect(f.isMonospaced)
    }

    @Test("tickerFont honors a custom weight")
    func tickerFontWeight() {
        let bold = Tokens.tickerFont(size: 12.0, weight: .bold)
        #expect(bold.isMonospaced)
        #expect(bold.pointSize == 12.0)
        #expect(bold.weight == .bold)
    }

    @Test("headerFont is a non-monospaced descriptor")
    func headerFontIsProportional() {
        // Headers (section titles, window titles) read better at larger
        // sizes when they are NOT mono-spaced. The shell still pairs them
        // with the mono ticks below.
        let h = Tokens.headerFont(size: 16.0)
        #expect(h.isMonospaced == false)
        #expect(h.pointSize == 16.0)
    }
}
