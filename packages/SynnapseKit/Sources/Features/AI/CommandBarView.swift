import SwiftUI
import DesignSystem

/// Spotlight-style command palette. Hosted in a `.sheet` on iOS and a
/// floating panel on macOS. Identity inherits the active shell —
/// Cockpit Dense paints the chrome.
@MainActor
public struct CommandBarView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable var viewModel: CommandBarViewModel
    var onSelectSuggestion: ((CommandSuggestion) -> Void)? = nil

    @FocusState private var focused: Bool

    public init(
        viewModel: CommandBarViewModel,
        onSelectSuggestion: ((CommandSuggestion) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onSelectSuggestion = onSelectSuggestion
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(spacing: 0) {
            field(tokens: tokens)
            Divider().opacity(0.4)
            content(tokens: tokens)
        }
        .background(tokens.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tokens.foregroundSecondary.color.opacity(0.18), lineWidth: 1)
        )
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640)
        .frame(maxHeight: 480)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func field(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tokens.accent.color)
            TextField(
                "Ask Synapse anything",
                text: $viewModel.query
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .font(tokens.tickerFont(size: 14))
            .foregroundStyle(tokens.foregroundPrimary.color)
            .onSubmit {
                viewModel.submit()
            }
            if viewModel.isStreaming {
                PhosphorPulse().frame(width: 28, height: 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func content(tokens: TokenSet) -> some View {
        if !viewModel.streamingAnswer.isEmpty {
            answerCard(tokens: tokens)
        } else {
            suggestionsList(tokens: tokens)
        }
    }

    @ViewBuilder
    private func answerCard(tokens: TokenSet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("ANSWER")
                        .font(tokens.tickerFont(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(tokens.accent.color)
                    Spacer()
                    if viewModel.isStreaming {
                        Text("streaming...")
                            .font(tokens.tickerFont(size: 9))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                }
                Text(viewModel.streamingAnswer)
                    .font(tokens.tickerFont(size: 12))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func suggestionsList(tokens: TokenSet) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.suggestions) { sugg in
                    Button {
                        viewModel.apply(sugg)
                        onSelectSuggestion?(sugg)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: iconName(for: sugg))
                                .font(.system(size: 11))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sugg.label)
                                    .font(tokens.tickerFont(size: 12, weight: .medium))
                                    .foregroundStyle(tokens.foregroundPrimary.color)
                                    .lineLimit(1)
                                if let subtitle = sugg.subtitle {
                                    Text(subtitle)
                                        .font(tokens.tickerFont(size: 10))
                                        .foregroundStyle(tokens.foregroundSecondary.color)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.3)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func iconName(for sugg: CommandSuggestion) -> String {
        switch sugg.kind {
        case .surface:     return "arrow.right.circle"
        case .savedQuery:  return "sparkle.magnifyingglass"
        case .askAdvisor:  return "person.bubble"
        }
    }
}
