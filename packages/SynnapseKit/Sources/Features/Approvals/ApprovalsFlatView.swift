import SwiftUI
import Models
import DesignSystem

/// Flat approvals surface. macOS gets `NavigationSplitView` with three panes
/// (filters / list / inspector). iOS gets a `NavigationStack` with a grouped
/// `List` and a pushed detail screen.
///
/// Per memory `feedback_workday_no_terminal_clicks`: the inspector is the only
/// place a Workday URL is offered, and there is no submit/save/cancel button.
@MainActor
public struct ApprovalsFlatView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: ApprovalsViewModel

    public init(viewModel: ApprovalsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(macOS)
        macLayout
            .task {
                if case .idle = viewModel.state { await viewModel.refresh() }
            }
        #else
        iosLayout
            .task {
                if case .idle = viewModel.state { await viewModel.refresh() }
            }
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            filtersSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            approvalsList
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                .navigationTitle("Approvals")
        } detail: {
            inspector
        }
    }

    private var filtersSidebar: some View {
        let tokens = theme.tokens(for: scheme)
        return List {
            Section("Status") {
                Button("All") { _ = viewModel.filter(searchText: "", status: .some(nil)) }
                ForEach(ApprovalStatus.allCases, id: \.self) { status in
                    Button(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) {
                        _ = viewModel.filter(status: .some(status))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .background(tokens.surface.color)
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        NavigationStack {
            approvalsList
                .navigationTitle("Approvals")
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: Binding(
                        get: { viewModel.searchText },
                        set: { _ = viewModel.filter(searchText: $0) }
                    ),
                    prompt: "Search approver, vendor, title"
                )
                .refreshable { await viewModel.refresh() }
                .navigationDestination(for: Approval.self) { approval in
                    let payload = inspectorPayload(for: approval)
                    ApprovalsInspector(payload: payload)
                        .navigationBarTitleDisplayMode(.inline)
                        .onAppear { viewModel.select(approval) }
                }
        }
    }
    #endif

    // MARK: - List + Inspector (shared)

    @ViewBuilder
    private var approvalsList: some View {
        let tokens = theme.tokens(for: scheme)
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                tokens.surface.color
                ProgressView().tint(tokens.foregroundSecondary.color)
            }
            .accessibilityIdentifier("approvals.loading")
        case .empty:
            ZStack {
                tokens.surface.color
                VStack(spacing: 6) {
                    Text("No approvals")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("New letters from Jacqulyn will land here.")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .accessibilityIdentifier("approvals.empty")
        case .results(let rows):
            #if os(iOS)
            List {
                ForEach(rows) { approval in
                    NavigationLink(value: approval) {
                        ApprovalRow(approval: approval, isSelected: false)
                    }
                    .listRowBackground(tokens.surface.color)
                }
            }
            .scrollContentBackground(.hidden)
            .background(tokens.background.color)
            #else
            List(selection: Binding<Approval?>(
                get: { viewModel.selected },
                set: { if let v = $0 { viewModel.select(v) } else { viewModel.clearSelection() } }
            )) {
                ForEach(rows) { approval in
                    ApprovalRow(approval: approval, isSelected: viewModel.selected == approval)
                        .tag(approval)
                }
            }
            .listStyle(.inset)
            .background(tokens.surface.color)
            #endif
        case .error(let message):
            ZStack {
                tokens.surface.color
                VStack(spacing: 6) {
                    Text("Couldn't load approvals")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .accessibilityIdentifier("approvals.error")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        let tokens = theme.tokens(for: scheme)
        if let approval = viewModel.selected {
            ApprovalsInspector(payload: inspectorPayload(for: approval))
        } else {
            ZStack {
                tokens.background.color
                Text("Select an approval")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    private func inspectorPayload(for approval: Approval) -> ApprovalInspectorPayload {
        let attached = viewModel.receipts(for: approval)
        let total = attached.reduce(Decimal.zero) { acc, r in acc + (r.amount ?? Decimal.zero) }
        return ApprovalInspectorPayload(
            approval: approval,
            receiptsAttached: attached,
            totalAmount: attached.isEmpty ? approval.totalAmount : total,
            currency: attached.first?.currency ?? approval.currency,
            status: approval.status,
            workdayURL: approval.workdayURL
        )
    }
}

/// Single row in the approvals list.
private struct ApprovalRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let approval: Approval
    let isSelected: Bool

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(approval.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(2)
                Spacer()
                Text(approval.status.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.accent.color)
            }
            HStack(spacing: 6) {
                Text(approval.approver)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text("·")
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text(approval.category)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
