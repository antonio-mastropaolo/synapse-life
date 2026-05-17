import SwiftUI
import DesignSystem
import Models

/// Top-level Dashboard surface — the inbox of un-reviewed transactions.
///
/// On macOS we render a two-column split: list on the left, inspector
/// on the right (Goals + Net this month). On iOS the list takes the
/// full width and the inspector cards collapse into the More tab; the
/// floating "Mark N" button anchors the bottom of the list.
@MainActor
public struct DashboardView: View {

    @Bindable private var viewModel: DashboardViewModel
    private var openGoals: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(
        viewModel: DashboardViewModel,
        openGoals: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.openGoals = openGoals
    }

    public var body: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(tokens: tokens)
                Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
                listScroll(tokens: tokens)
                Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
                footer(tokens: tokens)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.background.color)

            // Right inspector — fixed width on macOS so it doesn't fight
            // the list for horizontal space at the smallest window size.
            DashboardInspectorView(
                netThisMonth: viewModel.netThisMonth,
                goalsCurrency: defaultCurrency,
                openGoals: openGoals
            )
            .frame(width: 280)
            .background(tokens.background.color)
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header(tokens: tokens)
                Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
                listScroll(tokens: tokens)
            }
            .background(tokens.background.color)

            // Floating action button. Anchored to the safe-area
            // bottom; only painted when there's something selected.
            if viewModel.selectionCount > 0 {
                markReviewedButton(tokens: tokens)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.selectionCount)
    }
    #endif

    // MARK: - Header

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Dashboard")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - List

    @ViewBuilder
    private func listScroll(tokens: TokenSet) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if viewModel.sections.isEmpty {
                    emptyState(tokens: tokens)
                } else {
                    ForEach(viewModel.sections) { section in
                        sectionHeader(section: section, tokens: tokens)
                        ForEach(section.entries) { entry in
                            DashboardRowView(
                                entry: entry,
                                isSelected: bindingForSelection(of: entry.id)
                            )
                            Divider()
                                .background(tokens.foregroundSecondary.color.opacity(0.10))
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(section: DashboardSection, tokens: TokenSet) -> some View {
        HStack {
            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func emptyState(tokens: TokenSet) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(tokens.gainAccent.color)
            Text("Inbox zero")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Everything's been reviewed.")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(tokens: TokenSet) -> some View {
        HStack(spacing: 12) {
            Text(viewModel.footerCountText)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            markReviewedButton(tokens: tokens)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tokens.background.color)
    }

    @ViewBuilder
    private func markReviewedButton(tokens: TokenSet) -> some View {
        let n = viewModel.selectionCount
        let enabled = n > 0
        Button {
            _ = viewModel.markSelectedAsReviewed()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Mark \(n) as reviewed")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(enabled ? tokens.accent.color : tokens.surface.color)
            )
            .foregroundStyle(
                enabled
                ? Color.white
                : tokens.foregroundSecondary.color
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            enabled
            ? "Mark \(n) transactions as reviewed"
            : "Select a transaction to mark as reviewed"
        )
    }

    // MARK: - Bindings

    /// Returns a binding into the view model's selection set for a
    /// single row id. SwiftUI re-creates this binding every render,
    /// which is intentional — the read closure captures the id, not
    /// the live entry, so a row that scrolls off-screen does not
    /// hold onto stale state.
    private func bindingForSelection(of id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSelected(id) },
            set: { _ in viewModel.toggleSelection(id) }
        )
    }

    // MARK: - Locale

    /// Default currency for the inspector's net figure. Picked from
    /// the first transaction so a USD-only ledger never renders an
    /// EUR-shaped figure; the server-driven case will surface this
    /// as a future setting.
    private var defaultCurrency: String {
        viewModel.entries.first?.transaction.currency ?? "USD"
    }
}

#if DEBUG
@MainActor
public enum DashboardPreviewFactory {
    /// Builds a fully-seeded dashboard with the canonical demo data.
    /// Used by `#Preview` blocks and by snapshot tests that import
    /// the Features module.
    public static func demoViewModel() -> DashboardViewModel {
        DashboardViewModel(
            entries: DashboardDemoData.previewEntries,
            ledgerTotal: DashboardDemoData.ledgerTotal,
            calendar: DashboardDemoData.calendar,
            referenceDate: DashboardDemoData.referenceDate,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
#endif
