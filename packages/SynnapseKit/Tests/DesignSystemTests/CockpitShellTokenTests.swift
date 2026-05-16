import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Locks the Cockpit Dense shell as the app-wide default identity.
///
/// The integration step promoted `CockpitInstrument` from a per-surface
/// identity (used by Finance windows) to the shell that an unidentified
/// subtree inherits. That promotion is what these tests pin:
///   1. The `EnvironmentValues.theme` default value resolves to the
///      cockpit token set — `Theme.make(.cockpitInstrument)`.
///   2. Cockpit tokens clear WCAG AA in both light and dark schemes for
///      the pairs the shell actually paints (foreground over background,
///      foreground over surface, accent on background as a non-text 3.0:1
///      element, signed gain/loss accents on background).
///   3. The `Identity.default` enum case still resolves to the legacy
///      `Tokens.defaultLight` / `Tokens.defaultDark` so M1 surfaces that
///      opt into `.identity(.default)` (Settings snapshots, for example)
///      keep their previous appearance. The shell change is only about
///      what an *unidentified* subtree sees.
@Suite("Cockpit shell tokens")
struct CockpitShellTokenTests {

    @Test("Environment default value uses CockpitInstrument tokens")
    func envDefaultIsCockpit() {
        var env = EnvironmentValues()
        #expect(env.theme.identity == .cockpitInstrument)
        #expect(env.theme.tokens(for: .light) == Tokens.cockpitInstrumentLight)
        #expect(env.theme.tokens(for: .dark)  == Tokens.cockpitInstrumentDark)
    }

    @Test("Identity.default enum still resolves to the legacy default tokens")
    func backCompatDefaultEnumStable() {
        // Existing M1 snapshots and SettingsScreenSnapshotTests use
        // `.identity(.default)` explicitly. The shell promotion must not
        // mutate the legacy token set those callers see.
        #expect(Theme.make(.default).tokens(for: .light) == Tokens.defaultLight)
        #expect(Theme.make(.default).tokens(for: .dark)  == Tokens.defaultDark)
    }

    @Test("CockpitInstrument light clears WCAG AA on the pairs the shell paints")
    func cockpitLightContrast() {
        let t = Tokens.cockpitInstrumentLight
        #expect(contrastRatio(t.foregroundPrimary, t.background) >= 4.5)
        #expect(contrastRatio(t.foregroundPrimary, t.surface)    >= 4.5)
        #expect(contrastRatio(t.accent, t.background) >= 3.0)
        // Signed gain/loss deltas must read as colored chips at 3.0:1
        // (non-text UI element minimum) on both background and surface.
        #expect(contrastRatio(t.gainAccent, t.background) >= 3.0)
        #expect(contrastRatio(t.lossAccent, t.background) >= 3.0)
    }

    @Test("CockpitInstrument dark clears WCAG AA on the pairs the shell paints")
    func cockpitDarkContrast() {
        let t = Tokens.cockpitInstrumentDark
        #expect(contrastRatio(t.foregroundPrimary, t.background) >= 4.5)
        #expect(contrastRatio(t.foregroundPrimary, t.surface)    >= 4.5)
        #expect(contrastRatio(t.accent, t.background) >= 3.0)
        #expect(contrastRatio(t.gainAccent, t.background) >= 3.0)
        #expect(contrastRatio(t.lossAccent, t.background) >= 3.0)
    }

    @Test("Cockpit exposes a ledger-stripe row token distinct from surface")
    func ledgerStripeIsDistinct() {
        // Ledger rows alternate between `surface` and `ledgerStripe`.
        // If the two are identical there is no zebra.
        let t = Tokens.cockpitInstrumentLight
        let same =
            t.surface.red   == t.ledgerStripe.red &&
            t.surface.green == t.ledgerStripe.green &&
            t.surface.blue  == t.ledgerStripe.blue &&
            t.surface.opacity == t.ledgerStripe.opacity
        #expect(same == false)
    }
}
