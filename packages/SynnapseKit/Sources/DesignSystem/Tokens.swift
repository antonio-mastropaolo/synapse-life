import SwiftUI

/// Concrete RGB token used by the design system. We carry components as
/// `Double` so contrast math is exact and platform-agnostic — converting from
/// a `Color` back to components is lossy on Apple platforms.
public struct ColorToken: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// LIFE-identity-only tokens.
///
/// The Amber-Phosphor Terminal renders in a strict 3-color palette —
/// `phosphorBright` (peak amber), `phosphorDim` (dimmed amber for stale
/// values and scanline), and `terminalInk` (near-black background). These
/// tokens are wrapped in their own struct so other identities cannot
/// accidentally read or paint with them; a test asserts that
/// `TokenSet.life == nil` on every non-LIFE identity.
public struct LifeIdentityTokens: Sendable, Equatable {
    public let phosphorBright: ColorToken
    public let phosphorDim: ColorToken
    public let terminalInk: ColorToken

    public init(phosphorBright: ColorToken, phosphorDim: ColorToken, terminalInk: ColorToken) {
        self.phosphorBright = phosphorBright
        self.phosphorDim = phosphorDim
        self.terminalInk = terminalInk
    }
}

public struct TokenSet: Sendable, Equatable {
    public let background: ColorToken
    public let surface: ColorToken
    public let foregroundPrimary: ColorToken
    public let foregroundSecondary: ColorToken
    public let accent: ColorToken

    // MARK: - Finance-specific accents (M5)
    //
    // The CockpitInstrument identity extends with three finance tokens so the
    // ledger and money charts have a single source of truth for green/red and
    // for the ledger row stripe. Default values are derived from the base
    // identity so non-finance surfaces don't need to know about them.
    public let gainAccent: ColorToken
    public let lossAccent: ColorToken
    public let ledgerStripe: ColorToken

    // MARK: - LIFE-specific tokens (M6)
    //
    // Only the `.terminalAmber` identity exposes these; on every other
    // identity, `life == nil`. The terminal shader reads exactly these
    // three colors and nothing else. Locked by `LifeIdentityIsolationTests`.
    public let life: LifeIdentityTokens?

    public init(
        background: ColorToken,
        surface: ColorToken,
        foregroundPrimary: ColorToken,
        foregroundSecondary: ColorToken,
        accent: ColorToken,
        gainAccent: ColorToken? = nil,
        lossAccent: ColorToken? = nil,
        ledgerStripe: ColorToken? = nil,
        life: LifeIdentityTokens? = nil
    ) {
        self.background = background
        self.surface = surface
        self.foregroundPrimary = foregroundPrimary
        self.foregroundSecondary = foregroundSecondary
        self.accent = accent
        self.gainAccent = gainAccent ?? ColorToken(0.20, 0.78, 0.50)
        self.lossAccent = lossAccent ?? ColorToken(0.92, 0.32, 0.32)
        self.ledgerStripe = ledgerStripe ?? ColorToken(surface.red, surface.green, surface.blue, opacity: 0.55)
        self.life = life
    }
}

public enum Tokens {

    // MARK: - Default identity

    public static let defaultLight = TokenSet(
        background:         ColorToken(0.99, 0.99, 0.99),
        surface:            ColorToken(0.96, 0.96, 0.97),
        foregroundPrimary:  ColorToken(0.07, 0.07, 0.09),
        foregroundSecondary: ColorToken(0.30, 0.30, 0.34),
        accent:             ColorToken(0.16, 0.34, 0.78)
    )

    public static let defaultDark = TokenSet(
        background:         ColorToken(0.06, 0.06, 0.07),
        surface:            ColorToken(0.10, 0.10, 0.12),
        foregroundPrimary:  ColorToken(0.95, 0.95, 0.97),
        foregroundSecondary: ColorToken(0.70, 0.70, 0.74),
        accent:             ColorToken(0.55, 0.74, 1.00)
    )

    // MARK: - Terminal Amber (LIFE identity)
    //
    // Strict three colors per the synapse-v2 LIFE redesign (commit 58987c2).
    //   peak amber #FF7A00  → phosphorBright + foregroundPrimary + accent
    //   dim amber  #B35400  → phosphorDim + foregroundSecondary
    //   ink        #080604  → terminalInk + background + surface
    //
    // Anything outside this trio would violate the visual contract. Light
    // and dark resolve to the same set on purpose — terminal mode is the
    // identity, not a theme variant.

    private static let phosBright = ColorToken(1.00, 0.478, 0.000)
    private static let phosDim    = ColorToken(0.700, 0.329, 0.000)
    private static let phosInk    = ColorToken(0.031, 0.024, 0.016)

    public static let terminalAmberLight = TokenSet(
        background:         phosInk,
        surface:            phosInk,
        foregroundPrimary:  phosBright,
        foregroundSecondary: phosDim,
        accent:             phosBright,
        life: LifeIdentityTokens(
            phosphorBright: phosBright,
            phosphorDim:    phosDim,
            terminalInk:    phosInk
        )
    )

    public static let terminalAmberDark = terminalAmberLight

    // MARK: - Cockpit Instrument

    public static let cockpitInstrumentLight = TokenSet(
        background:         ColorToken(0.02, 0.02, 0.03),
        surface:            ColorToken(0.06, 0.06, 0.08),
        foregroundPrimary:  ColorToken(0.85, 0.92, 1.00),
        foregroundSecondary: ColorToken(0.55, 0.65, 0.78),
        accent:             ColorToken(0.20, 0.85, 0.65),
        // Finance accents tuned to read on top of the dark instrument
        // backplate. Green is shifted slightly cyan so it pairs with the
        // accent without becoming the accent. Red is muted vs the typical
        // SF Red so it does not overpower the panel.
        gainAccent:         ColorToken(0.30, 0.86, 0.62),
        lossAccent:         ColorToken(0.96, 0.42, 0.40),
        ledgerStripe:       ColorToken(0.10, 0.11, 0.14, opacity: 0.55)
    )

    public static let cockpitInstrumentDark = cockpitInstrumentLight

    // MARK: - Editorial

    public static let editorialLight = TokenSet(
        background:         ColorToken(0.98, 0.97, 0.94),
        surface:            ColorToken(0.94, 0.92, 0.88),
        foregroundPrimary:  ColorToken(0.10, 0.08, 0.06),
        foregroundSecondary: ColorToken(0.30, 0.27, 0.22),
        accent:             ColorToken(0.60, 0.10, 0.10)
    )

    public static let editorialDark = TokenSet(
        background:         ColorToken(0.10, 0.08, 0.06),
        surface:            ColorToken(0.14, 0.12, 0.10),
        foregroundPrimary:  ColorToken(0.96, 0.94, 0.90),
        foregroundSecondary: ColorToken(0.74, 0.70, 0.62),
        accent:             ColorToken(0.95, 0.60, 0.55)
    )
}

extension TokenSet {
    public func token(for identity: Identity, scheme: ColorScheme) -> TokenSet { self }
}
