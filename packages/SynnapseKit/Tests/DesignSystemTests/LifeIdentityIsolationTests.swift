import Foundation
import Testing
@testable import DesignSystem

/// LIFE-only tokens — `phosphorBright`, `phosphorDim`, `terminalInk` —
/// must be exposed by the `.terminalAmber` identity and only that
/// identity. Other identities returning a non-nil `life` block would
/// imply someone is reaching for the phosphor palette outside the LIFE
/// surface, which violates the strict 3-color visual contract.
@Suite("LifeIdentityIsolation")
struct LifeIdentityIsolationTests {

    @Test
    func terminalAmberExposesLifeTokens() {
        let theme = Theme.make(.terminalAmber)
        for scheme in [Theme.make(.terminalAmber).light, Theme.make(.terminalAmber).dark] {
            let life = try? #require(scheme.life)
            #expect(life != nil)
        }
        // Strict 3-color contract: bright != dim, both != ink, ink dark.
        let life = try? #require(theme.light.life)
        if let l = life {
            #expect(l.phosphorBright != l.phosphorDim)
            #expect(l.phosphorBright != l.terminalInk)
            #expect(l.phosphorDim != l.terminalInk)
            #expect(l.terminalInk.red < 0.1)
            #expect(l.terminalInk.green < 0.1)
            #expect(l.terminalInk.blue < 0.1)
        }
    }

    @Test
    func nonLifeIdentitiesDoNotExposeLifeTokens() {
        let banned: [Identity] = [.default, .cockpitInstrument, .editorial]
        for id in banned {
            let theme = Theme.make(id)
            #expect(theme.light.life == nil, "identity \(id) leaked life tokens (light)")
            #expect(theme.dark.life == nil, "identity \(id) leaked life tokens (dark)")
        }
    }
}
