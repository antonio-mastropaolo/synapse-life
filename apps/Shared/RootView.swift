import SwiftUI
import DesignSystem

@MainActor
public struct RootView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ZStack {
            tokens.background.color.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Synnapse")
                    .font(.system(size: 32, weight: .medium, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(theme.identity.rawValue)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }
}
