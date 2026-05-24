import SwiftUI
import Models
import DesignSystem

/// Sync/health surface for the per-account drill-down. Renders the
/// account's connection state at a glance: a colored dot that pulses
/// when fresh, a headline + relative timestamp, an institution /
/// kind / currency strip, and an actions row.
///
/// All decisions are derived from two `FinanceAccount` fields plus
/// the optional `viewModel.syncError`:
///
///   - `balanceCapturedAt` drives the dot color through three age
///     buckets (<6h green, <24h amber, older red) and the "Last sync
///     X ago" subline.
///   - `syncError` short-circuits the dot to red and unveils an
///     inline amber banner above the actions row.
///
/// The action buttons (Sync now, View statements, Disconnect) are
/// intentional no-ops at this layer — the surface is observational
/// until the live repository plumbs through a retry hook. The
/// banner's Retry button is wired the same way; pressing it logs
/// and clears nothing, but the call site is in place.
@MainActor
struct AccountSyncStatusCard: View {

    private let viewModel: AccountDetailViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Drives the green-dot pulse. Toggled on `.task` so we don't
    /// burn animation cycles when the dot is amber/red.
    @State private var pulse: Bool = false

    init(viewModel: AccountDetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(alignment: .leading, spacing: 16) {
            topRow(tokens: tokens)
            detailStrip(tokens: tokens)
            if let message = viewModel.syncError {
                errorBanner(message: message, tokens: tokens)
            }
            actionsRow(tokens: tokens)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
        .task {
            // Only the green case animates. Setting the flag on
            // appear and letting `withAnimation` carry it back and
            // forth gives the gentle 1-second opacity wobble.
            if status == .green {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
        }
    }

    // MARK: - Top row: dot + status copy

    private func topRow(tokens: TokenSet) -> some View {
        HStack(alignment: .center, spacing: 12) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(subline)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
        }
    }

    private var statusDot: some View {
        let color = status.color
        return Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .opacity(status == .green && pulse ? 0.55 : 1.0)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.30), lineWidth: 0.5)
            )
            .accessibilityLabel(Text(headline))
    }

    // MARK: - Detail strip

    private func detailStrip(tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 20) {
            miniStat(
                label: "Institution",
                value: viewModel.account.institutionName ?? "—",
                tokens: tokens
            )
            miniStat(
                label: "Account type",
                value: viewModel.account.kind.rawValue.capitalized,
                tokens: tokens
            )
            miniStat(
                label: "Currency",
                value: viewModel.account.currency,
                tokens: tokens
            )
        }
    }

    private func miniStat(label: String, value: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Error banner

    private func errorBanner(message: String, tokens: TokenSet) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.amber)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync error")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Self.amber)
                Text(message)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                print("[AccountSyncStatusCard] Retry sync requested for account \(viewModel.account.id).")
            } label: {
                Text("Retry sync")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(Self.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Self.amber.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accountSync.retry")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Self.amber.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Self.amber.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Actions row

    private func actionsRow(tokens: TokenSet) -> some View {
        HStack(spacing: 12) {
            Button {
                print("[AccountSyncStatusCard] Sync now requested for account \(viewModel.account.id).")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Sync now")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Self.amber)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accountSync.syncNow")

            Button {
                print("[AccountSyncStatusCard] View statements requested for account \(viewModel.account.id).")
            } label: {
                Text("View statements")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accountSync.viewStatements")

            Spacer()

            Button {
                print("[AccountSyncStatusCard] Disconnect requested for account \(viewModel.account.id).")
            } label: {
                Text("Disconnect account")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Self.danger)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accountSync.disconnect")
        }
    }

    // MARK: - Status derivation

    private enum Status {
        case green
        case amber
        case red

        var color: Color {
            switch self {
            case .green: return Color(red: 0.34, green: 0.78, blue: 0.50)
            case .amber: return Color(red: 1.00, green: 0.69, blue: 0.22)
            case .red:   return Color(red: 0.94, green: 0.33, blue: 0.56)
            }
        }
    }

    private var status: Status {
        if viewModel.syncError != nil { return .red }
        guard let captured = viewModel.account.balanceCapturedAt else { return .red }
        let hours = Date().timeIntervalSince(captured) / 3600
        if hours < 6  { return .green }
        if hours < 24 { return .amber }
        return .red
    }

    private var headline: String {
        if viewModel.syncError != nil { return "Sync error" }
        guard viewModel.account.balanceCapturedAt != nil else { return "Never synced" }
        switch status {
        case .green: return "Connected"
        case .amber: return "Sync delayed"
        case .red:   return "Sync error"
        }
    }

    private var subline: String {
        guard let captured = viewModel.account.balanceCapturedAt else {
            return "Never synced"
        }
        let relative = Self.relativeFormatter.localizedString(for: captured, relativeTo: Date())
        return "Last sync \(relative)"
    }

    // MARK: - Constants

    static let green  = Color(red: 0.34, green: 0.78, blue: 0.50)
    static let amber  = Color(red: 1.00, green: 0.69, blue: 0.22)
    static let danger = Color(red: 0.94, green: 0.33, blue: 0.56)

    /// Abbreviated relative formatter ("4 hr ago", "2 days ago"). Held
    /// statically because `RelativeDateTimeFormatter` is mildly heavy
    /// to construct and the output is locale-stable for our copy.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
