import SwiftUI
import AppKit
import DesignSystem
import Features
import Models

/// Live MY ACCOUNTS sidebar block — replaces the mock list that the
/// Copilot shell shipped with. Reads the resolved `[FinanceAccount]`
/// off [[FinanceAccountsViewModel]], groups them into the two
/// scannable buckets the reference shell uses (credit cards vs.
/// depository), and lights up the active row when routing is parked
/// on `.accountDetail(id:)`.
///
/// Drill-down: a row tap routes to `.accountDetail(id:)` via
/// [[RootShellViewModel.select(accountDetail:)]] — the detail pane
/// inside `CopilotShellMac` already knows how to render that case.
/// We deliberately do not call the legacy `select(account:)` slot
/// here: that slot is informational only and never swaps the pane.
///
/// Sync indicator: the only signal currently exposed on a flat
/// `FinanceAccount` is `balanceCapturedAt`. Until the wire row
/// surfaces `lastSyncError` on the per-account projection, the red
/// branch stays unreachable from this surface — `capturedAt` drives
/// green/amber and the red dot is wired through a single seam so
/// the integration is straightforward once that field lands.
@MainActor
struct CopilotSidebarAccounts: View {

    let accounts: FinanceAccountsViewModel
    @Bindable var routing: RootShellViewModel
    let chrome: CopilotTokens.Shell

    // Collapsible state — both groups open on first paint to match
    // the reference shell, but the operator can fold either away.
    @State private var creditExpanded: Bool = true
    @State private var depositoryExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MY ACCOUNTS")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.9)
                .foregroundStyle(chrome.foregroundSecondary.color)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)

            if accounts.accounts.isEmpty {
                emptyState
            } else {
                subgroup(
                    title: "Credit cards",
                    rows: creditCardAccounts,
                    isExpanded: $creditExpanded
                )

                subgroup(
                    title: "Depository",
                    rows: depositoryAccounts,
                    isExpanded: $depositoryExpanded
                )
            }
        }
    }

    // MARK: - Grouping

    private var creditCardAccounts: [FinanceAccount] {
        accounts.accounts.filter { $0.kind == .credit }
    }

    private var depositoryAccounts: [FinanceAccount] {
        accounts.accounts.filter { $0.kind == .checking || $0.kind == .savings }
    }

    // MARK: - Subgroup

    @ViewBuilder
    private func subgroup(
        title: String,
        rows: [FinanceAccount],
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(chrome.foregroundSecondary.color.opacity(0.85))
                        .frame(width: 10, alignment: .center)

                    Text(title)
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(chrome.foregroundSecondary.color.opacity(0.85))

                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .medium, design: .default))
                        .foregroundStyle(chrome.badgeForeground.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(chrome.badgeFill.color)
                        )

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("copilot.sidebar.accounts.group.\(title)")

            if isExpanded.wrappedValue {
                ForEach(rows) { account in
                    CopilotLiveAccountRow(
                        account: account,
                        isActive: isRowActive(account.id),
                        chrome: chrome
                    ) {
                        routing.select(accountDetail: account.id)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func isRowActive(_ id: String) -> Bool {
        if case .accountDetail(let activeId) = routing.selection {
            return activeId == id
        }
        return false
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No accounts yet")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(chrome.foregroundSecondary.color)
                .lineLimit(1)

            Button {
                // Add-account flow is owned by the onboarding wedge —
                // honour the same no-op contract A1's "+ Add account"
                // affordance carries so the sidebar surface stays
                // clickable without invoking a half-built sheet.
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add account")
                        .font(.system(size: 11, weight: .regular, design: .default))
                }
                .foregroundStyle(chrome.brandAccent.color)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("copilot.sidebar.accounts.addAccount")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

// MARK: - Live row

/// One row inside a MY ACCOUNTS subgroup. Mirrors the visual
/// treatment the mock `CopilotAccountRow` shipped with: 2pt
/// brand-accent edge bar when active, 8pt kind-colored swatch,
/// monospaced trailing balance pill. Adds a sync-state dot so the
/// operator can tell at a glance whether the figure is fresh.
@MainActor
private struct CopilotLiveAccountRow: View {
    let account: FinanceAccount
    let isActive: Bool
    let chrome: CopilotTokens.Shell
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(isActive ? chrome.brandAccent.color : Color.clear)
                    .frame(width: 2)

                Circle()
                    .fill(swatchColor(for: account.kind))
                    .frame(width: 8, height: 8)
                    .padding(.leading, 6)

                Text(account.name)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(
                        isActive || hover
                            ? chrome.foregroundPrimary.color
                            : chrome.foregroundSecondary.color
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .leading)

                syncDot
                    .frame(width: 6, height: 6)

                Spacer(minLength: 4)

                if let balance = account.currentBalance {
                    Text(formatCompact(balance))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(chrome.foregroundSecondary.color)
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? chrome.activeRowBackground.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hover = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityLabel(account.name)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - Sync state

    /// Sync-state indicator dot.
    /// - green: captured within the last 6 hours
    /// - amber: captured but ≥6h ago (or never captured)
    /// - red: explicit sync error — reserved for the seam where
    ///   `FinanceAccount` starts carrying the parent item's
    ///   `lastSyncError`. Stays unreachable today.
    @ViewBuilder
    private var syncDot: some View {
        Circle().fill(syncDotColor)
    }

    private var syncDotColor: Color {
        if hasSyncError { return .red }
        guard let captured = account.balanceCapturedAt else {
            return .orange
        }
        let stale = Date().timeIntervalSince(captured) >= (6 * 60 * 60)
        return stale ? .orange : .green
    }

    /// `FinanceAccount` does not currently expose the parent item's
    /// `lastSyncError`. The wire model has it; the projection layer
    /// strips it. Once the projection plumbs the field, this returns
    /// `account.lastSyncError != nil` and the red dot lights up.
    private var hasSyncError: Bool {
        false
    }

    // MARK: - Swatch

    private func swatchColor(for kind: AccountKind) -> Color {
        switch kind {
        case .credit:     return .orange
        case .checking:   return Color(red: 0.32, green: 0.62, blue: 0.95)
        case .savings:    return Color(red: 0.35, green: 0.75, blue: 0.55)
        case .brokerage:  return Color(red: 0.78, green: 0.55, blue: 0.95)
        case .retirement: return Color(red: 0.95, green: 0.78, blue: 0.30)
        case .loan:       return Color(red: 0.92, green: 0.40, blue: 0.45)
        case .other:      return Color.gray
        }
    }

    // MARK: - Balance formatting

    /// Compact dollar form ("$1,053", "$12.3k"). Uses the host
    /// locale's grouping. Matches the trailing-balance shape the
    /// mock rows used ("$1,053") so the visual rhythm survives the
    /// live-data swap.
    private func formatCompact(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        let absolute = abs(doubleValue)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = account.currency.isEmpty ? "USD" : account.currency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0

        if absolute >= 1_000_000 {
            formatter.maximumFractionDigits = 1
            let millions = doubleValue / 1_000_000
            let body = formatter.string(from: NSNumber(value: millions)) ?? "$0"
            return "\(body)M"
        }
        if absolute >= 10_000 {
            let thousands = Int((doubleValue / 1_000).rounded())
            let body = formatter.string(from: NSNumber(value: thousands)) ?? "$0"
            return "\(body)k"
        }
        return formatter.string(from: NSNumber(value: doubleValue)) ?? "$0"
    }
}
