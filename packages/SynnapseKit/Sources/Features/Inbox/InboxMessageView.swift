import SwiftUI
import Models
import DesignSystem

/// Detail view for one inbox message. Read-only: shows sender, subject,
/// timestamp, source, and the full body. No compose / reply / send.
@MainActor
public struct InboxMessageView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    private let item: InboxItem

    public init(item: InboxItem) {
        self.item = item
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(tokens: tokens)
                Divider().opacity(0.2)
                body(tokens: tokens)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
        .accessibilityLabel("Message from \(item.senderDisplay): \(item.displaySubject)")
    }

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.displaySubject)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.senderDisplay)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(item.sender)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.source.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.accent.color)
                    Text(dateString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
        }
    }

    @ViewBuilder
    private func body(tokens: TokenSet) -> some View {
        Text(item.body)
            .font(.system(size: 13))
            .foregroundStyle(tokens.foregroundPrimary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(2)
            .textSelection(.enabled)
    }

    private var dateString: String {
        // Fixed reference date for deterministic snapshots — we anchor at
        // 2026-05-15 14:30 UTC. Real runs swap this for `Date()`.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: item.receivedAt)
    }
}
