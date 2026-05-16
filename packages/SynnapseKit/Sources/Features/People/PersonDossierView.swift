import SwiftUI
import Models
import DesignSystem

/// Per-identity dossier surface. On macOS, this is the third pane of the
/// `NavigationSplitView` when a person is selected. On iOS, it presents as a
/// modal `.sheet`. Read-only in M7 — no compose, no reply, no edit.
@MainActor
public struct PersonDossierView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    private let person: Person
    private let dossier: PersonDossier?
    private let isLoading: Bool
    private let error: String?

    public init(
        person: Person,
        dossier: PersonDossier?,
        isLoading: Bool = false,
        error: String? = nil
    ) {
        self.person = person
        self.dossier = dossier
        self.isLoading = isLoading
        self.error = error
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(tokens: tokens)
                stats(tokens: tokens)
                if let dossier {
                    if !dossier.openActionItems.isEmpty {
                        section("Open with you", tokens: tokens) {
                            ForEach(dossier.openActionItems) { item in
                                actionItemRow(item, tokens: tokens)
                            }
                        }
                    }
                    if !dossier.recentMessages.isEmpty {
                        section("Recent messages", tokens: tokens) {
                            ForEach(dossier.recentMessages) { message in
                                messageRow(message, tokens: tokens)
                            }
                        }
                    }
                } else if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().tint(tokens.foregroundSecondary.color)
                        Text("Loading dossier")
                            .font(.system(size: 12))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
                } else if let error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dossier for \(person.displayName)")
    }

    // MARK: - Pieces

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        HStack(spacing: 12) {
            avatar(tokens: tokens)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(person.identity)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                if let notes = person.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if person.kind == .entity {
                Text("ENTITY")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.accent.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(tokens.accent.color.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func avatar(tokens: TokenSet) -> some View {
        ZStack {
            Circle()
                .fill(tokens.surface.color)
            Text(initials(of: person.displayName))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
        .frame(width: 48, height: 48)
        .overlay(
            Circle()
                .stroke(tokens.foregroundSecondary.color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func stats(tokens: TokenSet) -> some View {
        HStack(spacing: 18) {
            stat(label: "MESSAGES",
                 value: "\(person.totalMessages)",
                 tokens: tokens)
            stat(label: "OPEN",
                 value: "\(person.openActions)",
                 tokens: tokens)
            stat(label: "AWAITING",
                 value: "\(person.awaitingMyReply)",
                 tokens: tokens)
            stat(label: "THREADS",
                 value: "\(person.distinctThreads)",
                 tokens: tokens)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func stat(label: String, value: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.08)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }

    @ViewBuilder
    private func section<C: View>(
        _ title: String,
        tokens: TokenSet,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.08)
                .foregroundStyle(tokens.foregroundSecondary.color)
            content()
        }
    }

    @ViewBuilder
    private func messageRow(_ m: DossierMessage, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(m.subject ?? "(no subject)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Spacer()
                if m.awaitingMyReply {
                    Text("REPLY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.accent.color)
                }
            }
            HStack(spacing: 6) {
                Text(m.source.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("·")
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text(relativeDate(m.receivedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(tokens.surface.color)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tokens.foregroundSecondary.color.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionItemRow(_ a: DossierActionItem, tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(tokens.accent.color)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.text)
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                if let subject = a.messageSubject {
                    Text(subject)
                        .font(.system(size: 10))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ")
        let chars: [Character] = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date(timeIntervalSince1970: 1_747_500_000))
    }
}
