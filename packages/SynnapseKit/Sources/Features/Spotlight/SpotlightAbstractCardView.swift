import SwiftUI
import DesignSystem

@MainActor
public struct SpotlightAbstractCardView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    private let abstract: FormattedAbstract
    private let title: String

    public init(title: String, abstract: FormattedAbstract) {
        self.title = title
        self.abstract = abstract
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        let isEditorial = theme.identity == .editorial
        let face: Font.Design = isEditorial ? .serif : .monospaced

        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(abstract.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 13, weight: .regular, design: face))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityLabel(line)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.20), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Abstract for \(title)"))
    }
}
