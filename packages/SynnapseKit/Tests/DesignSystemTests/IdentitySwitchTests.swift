import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Identity switch")
struct IdentitySwitchTests {

    @Test("Theme.make returns the requested identity")
    func makeReturnsRequestedIdentity() {
        #expect(Theme.make(.default).identity == .default)
        #expect(Theme.make(.terminalAmber).identity == .terminalAmber)
        #expect(Theme.make(.cockpitInstrument).identity == .cockpitInstrument)
        #expect(Theme.make(.editorial).identity == .editorial)
    }

    @Test("Each identity carries distinct background tokens")
    func identitiesAreDistinct() {
        let bgs = Identity.allCases.map { Theme.make($0).light.background }
        let uniqued = Set(bgs.map { "\($0.red),\($0.green),\($0.blue)" })
        #expect(uniqued.count == Identity.allCases.count)
    }

    @Test("Environment default value is the default identity")
    func environmentDefault() {
        var env = EnvironmentValues()
        #expect(env.theme.identity == .default)
        env.theme = .make(.terminalAmber)
        #expect(env.theme.identity == .terminalAmber)
    }

    @Test("Scheme selector returns the matching token set")
    func schemeSelector() {
        let theme = Theme.make(.default)
        #expect(theme.tokens(for: .light) == Tokens.defaultLight)
        #expect(theme.tokens(for: .dark)  == Tokens.defaultDark)
    }
}
