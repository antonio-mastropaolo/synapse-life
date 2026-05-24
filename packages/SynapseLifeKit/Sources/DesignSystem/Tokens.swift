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

    // MARK: - Finance-specific accents (M5)
    //
    // The CockpitInstrument identity extends with three finance tokens so the
    // ledger and money charts have a single source of truth for green/red and
    // for the ledger row stripe. Default values are derived from the base
    // identity so non-finance surfaces don't need to know about them.
    public let gainAccent: ColorToken
    public let lossAccent: ColorToken
    public let ledgerStripe: ColorToken

    public init(
        background: ColorToken,
        surface: ColorToken,
        foregroundPrimary: ColorToken,
        foregroundSecondary: ColorToken,
        accent: ColorToken,
        gainAccent: ColorToken? = nil,
        lossAccent: ColorToken? = nil,
        ledgerStripe: ColorToken? = nil
    ) {
        self.background = background
        self.surface = surface
        self.foregroundPrimary = foregroundPrimary
        self.foregroundSecondary = foregroundSecondary
        self.accent = accent
        self.gainAccent = gainAccent ?? ColorToken(0.20, 0.56, 0.36)
        self.lossAccent = lossAccent ?? ColorToken(0.85, 0.27, 0.27)
        self.ledgerStripe = ledgerStripe ?? ColorToken(surface.red, surface.green, surface.blue, opacity: 0.55)
    }
}

public enum Tokens {

    // MARK: - Default identity
    //
    // Apple-system neutral. Light leans on a paper-white canvas with a
    // faintly lifted surface so cards read as floating panes under soft
    // depth. Dark is a true neutral graphite — not blue-black — matching
    // the current system look. The accent is one restrained system blue,
    // brightened in dark to stay legible on the graphite base.

    public static let defaultLight = TokenSet(
        background:         ColorToken(0.97, 0.97, 0.98),
        surface:            ColorToken(1.00, 1.00, 1.00),
        foregroundPrimary:  ColorToken(0.07, 0.07, 0.09),
        foregroundSecondary: ColorToken(0.36, 0.37, 0.41),
        accent:             ColorToken(0.00, 0.40, 0.84)
    )

    public static let defaultDark = TokenSet(
        background:         ColorToken(0.07, 0.07, 0.08),
        surface:            ColorToken(0.12, 0.12, 0.13),
        foregroundPrimary:  ColorToken(0.96, 0.96, 0.97),
        foregroundSecondary: ColorToken(0.66, 0.67, 0.71),
        accent:             ColorToken(0.39, 0.65, 1.00)
    )

    // MARK: - Cockpit Instrument
    //
    // The app-wide shell identity. Dark by design (the finance instrument
    // language), but refreshed away from the old teal-tinted void toward a
    // refined neutral graphite that reads as current system dark. A single
    // restrained accent — a soft system-leaning teal-blue — carries
    // interactive emphasis. Finance gain/loss accents are tuned to read on
    // the graphite backplate without fighting the accent.

    public static let cockpitInstrumentLight = TokenSet(
        background:         ColorToken(0.055, 0.058, 0.066),
        surface:            ColorToken(0.105, 0.110, 0.122),
        foregroundPrimary:  ColorToken(0.93, 0.94, 0.96),
        foregroundSecondary: ColorToken(0.62, 0.64, 0.69),
        accent:             ColorToken(0.32, 0.68, 0.96),
        // Gain green sits cooler so it pairs with the accent without
        // becoming it. Loss is a refined system red, muted just enough to
        // not overpower the panel. Both clear 3.0:1 on the graphite ground.
        gainAccent:         ColorToken(0.31, 0.80, 0.55),
        lossAccent:         ColorToken(0.95, 0.42, 0.42),
        ledgerStripe:       ColorToken(0.155, 0.160, 0.175, opacity: 0.55)
    )

    public static let cockpitInstrumentDark = cockpitInstrumentLight

    // MARK: - Editorial
    //
    // Warm-paper identity, modernized: slightly less saturated cream, a
    // refined crimson accent that holds 3.0:1 on the paper ground.

    public static let editorialLight = TokenSet(
        background:         ColorToken(0.98, 0.97, 0.95),
        surface:            ColorToken(1.00, 0.99, 0.97),
        foregroundPrimary:  ColorToken(0.11, 0.09, 0.07),
        foregroundSecondary: ColorToken(0.36, 0.32, 0.27),
        accent:             ColorToken(0.66, 0.13, 0.13)
    )

    public static let editorialDark = TokenSet(
        background:         ColorToken(0.10, 0.09, 0.07),
        surface:            ColorToken(0.15, 0.13, 0.11),
        foregroundPrimary:  ColorToken(0.97, 0.95, 0.91),
        foregroundSecondary: ColorToken(0.74, 0.70, 0.63),
        accent:             ColorToken(0.96, 0.62, 0.57)
    )

    // MARK: - Cockpit Dense shell typography
    //
    // The shell paints ticker rows, ledger rows, and the sidebar tree at
    // an 11pt SF Mono base. Section headers fall back to SF Pro at a
    // larger size. These helpers exist so callers can ask for the shell's
    // canonical fonts without needing to know about platform descriptors.

    /// Canonical base size for ticker / ledger / tree rows in the shell.
    public static let tickBaseSize: CGFloat = 11.0

    /// A monospaced descriptor at `size` (defaults to `tickBaseSize`).
    /// Used by every row that needs aligned columns — ledger rows, tick
    /// rows, the sidebar tree.
    public static func tickerFont(
        size: CGFloat = tickBaseSize,
        weight: ShellFontWeight = .regular
    ) -> ShellFontDescriptor {
        ShellFontDescriptor(pointSize: size, weight: weight, isMonospaced: true)
    }

    /// A proportional (SF Pro–style) descriptor for headers. Pairs with
    /// `tickerFont` rows below.
    public static func headerFont(
        size: CGFloat,
        weight: ShellFontWeight = .semibold
    ) -> ShellFontDescriptor {
        ShellFontDescriptor(pointSize: size, weight: weight, isMonospaced: false)
    }
}

/// Platform-agnostic font weight enum used by the shell typography
/// helpers. Maps cleanly to `Font.Weight` at the SwiftUI boundary.
public enum ShellFontWeight: Sendable, Equatable {
    case regular, medium, semibold, bold

    public var swiftUIWeight: Font.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        }
    }
}

/// Carries the shell's canonical typography choices through DesignSystem
/// without leaking `UIFont` / `NSFont` types into shared code. Callers
/// turn it into a `Font` via `swiftUIFont` at the SwiftUI boundary.
public struct ShellFontDescriptor: Sendable, Equatable {
    public let pointSize: CGFloat
    public let weight: ShellFontWeight
    public let isMonospaced: Bool

    public init(pointSize: CGFloat, weight: ShellFontWeight, isMonospaced: Bool) {
        self.pointSize = pointSize
        self.weight = weight
        self.isMonospaced = isMonospaced
    }

    /// SwiftUI font at this descriptor's size + weight + design.
    public var swiftUIFont: Font {
        let design: Font.Design = isMonospaced ? .monospaced : .default
        return .system(size: pointSize, weight: weight.swiftUIWeight, design: design)
    }
}

extension TokenSet {
    public func token(for identity: Identity, scheme: ColorScheme) -> TokenSet { self }
}
