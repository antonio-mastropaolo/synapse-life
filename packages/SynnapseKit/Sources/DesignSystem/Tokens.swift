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

public struct TokenSet: Sendable, Equatable {
    public let background: ColorToken
    public let surface: ColorToken
    public let foregroundPrimary: ColorToken
    public let foregroundSecondary: ColorToken
    public let accent: ColorToken

    public init(
        background: ColorToken,
        surface: ColorToken,
        foregroundPrimary: ColorToken,
        foregroundSecondary: ColorToken,
        accent: ColorToken
    ) {
        self.background = background
        self.surface = surface
        self.foregroundPrimary = foregroundPrimary
        self.foregroundSecondary = foregroundSecondary
        self.accent = accent
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

    // MARK: - Terminal Amber

    public static let terminalAmberLight = TokenSet(
        background:         ColorToken(0.05, 0.04, 0.03),
        surface:            ColorToken(0.09, 0.07, 0.04),
        foregroundPrimary:  ColorToken(1.00, 0.75, 0.20),
        foregroundSecondary: ColorToken(0.75, 0.55, 0.14),
        accent:             ColorToken(1.00, 0.55, 0.10)
    )

    public static let terminalAmberDark = terminalAmberLight

    // MARK: - Cockpit Instrument

    public static let cockpitInstrumentLight = TokenSet(
        background:         ColorToken(0.02, 0.02, 0.03),
        surface:            ColorToken(0.06, 0.06, 0.08),
        foregroundPrimary:  ColorToken(0.85, 0.92, 1.00),
        foregroundSecondary: ColorToken(0.55, 0.65, 0.78),
        accent:             ColorToken(0.20, 0.85, 0.65)
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
