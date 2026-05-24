import SwiftUI
import DesignSystem
import Models

/// Minimal SwiftUI host for the weekly digest.
///
/// Added 2026-05-17 during the four-branch Copilot integration. The
/// AI++ wedge shipped `DigestViewModel` without a view; this is the
/// minimum-viable surface so the INTELLIGENCE sidebar row has
/// something to route to. The visual treatment matches the Copilot
/// chrome (dark surface, mono labels, accented bullets) so it lives
/// natively inside `CopilotShellMac` without a per-view identity
/// override.
///
/// When agent 5 ships a richer digest view, swap this surface for it
/// and keep `DigestViewModel` as the source of truth.
@MainActor
public struct DigestView: View {

    @Bindable private var viewModel: DigestViewModel
    private let onCitationTap: (@MainActor (String) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(
        viewModel: DigestViewModel,
        onCitationTap: (@MainActor (String) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onCitationTap = onCitationTap
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(tokens: tokens)

                if viewModel.isLoading && viewModel.digest == nil {
                    loadingState(tokens: tokens)
                } else if let digest = viewModel.digest {
                    bulletsList(digest: digest, tokens: tokens)
                } else if let err = viewModel.lastError {
                    errorState(message: err, tokens: tokens)
                } else {
                    emptyState(tokens: tokens)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("intelligence.digest")
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WEEKLY DIGEST")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            if let d = viewModel.digest {
                Text(d.greeting)
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(weekRange(start: d.weekStart, end: d.weekEnd))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            } else {
                Text("This week, at a glance")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
        }
    }

    @ViewBuilder
    private func bulletsList(digest: Digest, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(digest.bullets) { bullet in
                bulletRow(bullet: bullet, tokens: tokens)
            }
        }
    }

    @ViewBuilder
    private func bulletRow(bullet: DigestBullet, tokens: TokenSet) -> some View {
        // Tapping a bullet jumps to its first citation. Multi-citation
        // bullets show the count; the host can replace this with a
        // proper popover when richer routing is needed.
        Button {
            if let first = bullet.citations.first {
                onCitationTap?(first)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(accentColor(for: bullet.kind, tokens: tokens))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bullet.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(bullet.body)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !bullet.citations.isEmpty {
                        Text("\(bullet.citations.count) cited")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color.opacity(0.7))
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.foregroundPrimary.color.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(bullet.citations.isEmpty)
    }

    @ViewBuilder
    private func loadingState(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Reading your week…")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func errorState(message: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Digest unavailable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func emptyState(tokens: TokenSet) -> some View {
        Text("No digest yet. Refresh once your week has a few transactions.")
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(tokens.foregroundSecondary.color)
    }

    // MARK: - Helpers

    private func accentColor(for kind: DigestBullet.Kind, tokens: TokenSet) -> Color {
        switch kind {
        case .spend:         return tokens.category(.fees)
        case .income:        return tokens.category(.income)
        case .net:           return tokens.accent.color
        case .topCategory:   return tokens.category(.restaurants)
        case .subscriptions: return tokens.category(.subscriptions)
        case .anomaly:       return tokens.category(.loans)
        case .suggestion:    return tokens.category(.transfers)
        }
    }

    private func weekRange(start: Date, end: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        // End is exclusive — subtract one day for the display range.
        let endShown = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(df.string(from: start)) — \(df.string(from: endShown))"
    }
}
