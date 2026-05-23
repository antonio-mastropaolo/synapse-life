import SwiftUI

public enum Identity: String, Sendable, CaseIterable, Equatable {
    case `default`
    case terminalAmber
    case cockpitInstrument
    case editorial
}

public struct Theme: Sendable, Equatable {
    public let identity: Identity
    public let light: TokenSet
    public let dark: TokenSet

    public init(identity: Identity, light: TokenSet, dark: TokenSet) {
        self.identity = identity
        self.light = light
        self.dark = dark
    }

    public func tokens(for scheme: ColorScheme) -> TokenSet {
        switch scheme {
        case .dark: return dark
        default:    return light
        }
    }

    public static func make(_ identity: Identity) -> Theme {
        switch identity {
        case .default:
            return Theme(identity: .default,
                         light: Tokens.defaultLight,
                         dark:  Tokens.defaultDark)
        case .terminalAmber:
            return Theme(identity: .terminalAmber,
                         light: Tokens.terminalAmberLight,
                         dark:  Tokens.terminalAmberDark)
        case .cockpitInstrument:
            return Theme(identity: .cockpitInstrument,
                         light: Tokens.cockpitInstrumentLight,
                         dark:  Tokens.cockpitInstrumentDark)
        case .editorial:
            return Theme(identity: .editorial,
                         light: Tokens.editorialLight,
                         dark:  Tokens.editorialDark)
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    // App-wide shell: an unidentified subtree resolves to the Cockpit
    // Dense identity. The `.default` enum case still exists and still
    // resolves to the legacy `Tokens.defaultLight` / `Tokens.defaultDark`
    // for callers that apply `.identity(.default)` explicitly (covered by
    // [[backCompatDefaultEnumStable]]).
    static let defaultValue: Theme = .make(.cockpitInstrument)
}

extension EnvironmentValues {
    public var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies the given visual identity to the subtree. Outer subtrees keep
    /// whatever identity they had before.
    public func identity(_ identity: Identity) -> some View {
        environment(\.theme, .make(identity))
    }
}
