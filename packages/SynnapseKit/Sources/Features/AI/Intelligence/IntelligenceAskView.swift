import SwiftUI
import DesignSystem
import Models

/// Dedicated Ask sheet — the new single Ask UX after the four-branch
/// Copilot integration on 2026-05-17. Replaces the legacy
/// `CommandBarView` answer surface; the entry keystroke (`⌘K` on
/// macOS, the sparkles toolbar item on iOS) now hosts this view
/// inside a sheet/overlay.
///
/// Per AI++ manifest section 5:
///   - Render the streamed answer
///   - Paint citation chips below it
///   - Show a small route badge (On-device / Server) next to the
///     answer so the operator knows where the response came from
///   - Tap on a chip routes by `AskCitation.Kind`
///
/// The host owns the dismissal and the citation routing — pass a
/// callback for chip taps so the surface stays decoupled from the
/// app shell's URL handler.
@MainActor
public struct IntelligenceAskView: View {

    @Bindable private var viewModel: IntelligenceAskViewModel
    private let onCitationTap: (@MainActor (AskCitation) -> Void)?
    private let onDismiss: (@MainActor () -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @FocusState private var queryFocused: Bool

    public init(
        viewModel: IntelligenceAskViewModel,
        onCitationTap: (@MainActor (AskCitation) -> Void)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onCitationTap = onCitationTap
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)

        VStack(alignment: .leading, spacing: 14) {
            header(tokens: tokens)
            queryField(tokens: tokens)
            if !viewModel.streamingAnswer.isEmpty || viewModel.isStreaming {
                answerBlock(tokens: tokens)
            }
            if !viewModel.citations.isEmpty {
                citationChips(tokens: tokens)
            }
            if let err = viewModel.lastError {
                Text(err)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.category(.loans))
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tokens.background.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        .onAppear { queryFocused = true }
        .accessibilityIdentifier("intelligence.ask")
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(tokens.accent.color)
            Text("ASK SYNAPSE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            routeBadge(tokens: tokens)
            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    @ViewBuilder
    private func routeBadge(tokens: TokenSet) -> some View {
        let label: String = {
            switch viewModel.route {
            case .appleIntelligence: return "ON-DEVICE"
            case .server:            return "SERVER"
            }
        }()
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(tokens.foregroundSecondary.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                Capsule().stroke(tokens.foregroundSecondary.color.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel("Route: \(label)")
    }

    @ViewBuilder
    private func queryField(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(tokens.foregroundSecondary.color)
            TextField("Ask anything about your money…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .focused($queryFocused)
                .onSubmit { viewModel.submit() }
            if viewModel.isStreaming {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func answerBlock(tokens: TokenSet) -> some View {
        Text(viewModel.streamingAnswer.isEmpty ? "Thinking…" : viewModel.streamingAnswer)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(tokens.foregroundPrimary.color)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.foregroundPrimary.color.opacity(0.03))
            )
            .accessibilityIdentifier("intelligence.ask.answer")
    }

    @ViewBuilder
    private func citationChips(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CITATIONS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundSecondary.color)
            // Wrap citation chips with a simple HFlowLayout-ish stack —
            // SwiftUI's `Layout` would be ideal but a plain HStack with
            // a fixed-width parent reads cleanly enough at this scale.
            HStack(spacing: 6) {
                ForEach(viewModel.citations.prefix(4)) { citation in
                    Button {
                        onCitationTap?(citation)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chipIcon(for: citation.kind))
                                .font(.system(size: 10))
                            Text(citation.label)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(tokens.accent.color.opacity(0.12))
                        )
                        .overlay(
                            Capsule().stroke(tokens.accent.color.opacity(0.4), lineWidth: 1)
                        )
                        .foregroundStyle(tokens.accent.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Citation: \(citation.label)")
                }
            }
        }
    }

    private func chipIcon(for kind: AskCitation.Kind) -> String {
        switch kind {
        case .transaction: return "arrow.left.arrow.right"
        case .account:     return "creditcard"
        case .category:    return "tag"
        case .insight:     return "lightbulb"
        }
    }
}
