import SwiftUI
import Models
import DesignSystem

/// Hierarchical view over `[ApprovalTreeNode]` using `OutlineGroup` inside a
/// `List`. macOS gets a master/detail split; iOS gets a stack with the tree
/// in the root and the inspector pushed.
///
/// The disclosure-arrow animation is disabled when `accessibilityReduceMotion`
/// is true — per HIG and the project rule about respecting Reduce Motion
/// system-wide.
@MainActor
public struct ApprovalsTreeView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable private var viewModel: ApprovalsTreeViewModel

    public init(viewModel: ApprovalsTreeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(macOS)
        NavigationSplitView {
            content
                .navigationTitle("Approvals · Tree")
                .toolbar { toolbarContent }
                .frame(minWidth: 320)
        } detail: {
            detail
        }
        .task {
            if case .idle = viewModel.state { await viewModel.refresh() }
        }
        #else
        NavigationStack {
            content
                .navigationTitle("Approvals · Tree")
                .toolbar { toolbarContent }
                .navigationDestination(for: Approval.self) { approval in
                    ApprovalsInspector(payload: viewModel.inspector(for: approval))
                        .navigationBarTitleDisplayMode(.inline)
                        .onAppear { viewModel.select(approval) }
                }
                .refreshable { await viewModel.refresh() }
        }
        .task {
            if case .idle = viewModel.state { await viewModel.refresh() }
        }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button("Expand all") { viewModel.expandAll() }
                .accessibilityIdentifier("approvals.tree.expand-all")
            Button("Collapse all") { viewModel.collapseAll() }
                .accessibilityIdentifier("approvals.tree.collapse-all")
        }
    }

    @ViewBuilder
    private var content: some View {
        let tokens = theme.tokens(for: scheme)
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                tokens.surface.color
                ProgressView().tint(tokens.foregroundSecondary.color)
            }
            .accessibilityIdentifier("approvals.tree.loading")
        case .empty:
            ZStack {
                tokens.surface.color
                Text("No approvals yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .accessibilityIdentifier("approvals.tree.empty")
        case .results(let nodes):
            outline(nodes: nodes, tokens: tokens)
        case .error(let message):
            ZStack {
                tokens.surface.color
                VStack(spacing: 4) {
                    Text("Couldn't load approvals")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .accessibilityIdentifier("approvals.tree.error")
        }
    }

    @ViewBuilder
    private func outline(nodes: [ApprovalTreeNode], tokens: TokenSet) -> some View {
        let displayNodes = nodes.map { DisplayNode(from: $0) }
        let listView = List {
            ForEach(displayNodes) { node in
                if node.isLeaf {
                    leafRow(node: node, tokens: tokens)
                } else {
                    DisclosureGroup(
                        isExpanded: Binding<Bool>(
                            get: { viewModel.isExpanded(node.approvalID ?? "") },
                            set: { _ in viewModel.toggle(node.approvalID ?? "") }
                        )
                    ) {
                        ForEach(node.children) { child in
                            leafRow(node: child, tokens: tokens)
                        }
                    } label: {
                        approvalRow(node: node, tokens: tokens)
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(tokens.surface.color)
        .scrollContentBackground(.hidden)

        if reduceMotion {
            listView.transaction { $0.animation = nil }
        } else {
            listView
        }
    }

    @ViewBuilder
    private func approvalRow(node: DisplayNode, tokens: TokenSet) -> some View {
        if let approval = node.approval {
            Button {
                viewModel.select(approval)
            } label: {
                HStack(spacing: 8) {
                    Text(approval.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .lineLimit(2)
                    Spacer()
                    Text("\(node.children.count) rec.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text(approval.status.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.accent.color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func leafRow(node: DisplayNode, tokens: TokenSet) -> some View {
        if let receipt = node.receipt {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text(receipt.vendor)
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Spacer()
                Text(receipt.date)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Text(amountString(receipt))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var detail: some View {
        let tokens = theme.tokens(for: scheme)
        if let approval = viewModel.selected {
            ApprovalsInspector(payload: viewModel.inspector(for: approval))
        } else {
            ZStack {
                tokens.background.color
                Text("Select an approval")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    private func amountString(_ r: Receipt) -> String {
        guard let v = r.amount else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: v as NSDecimalNumber) ?? "—"
    }
}

/// Internal flattening of `ApprovalTreeNode` for OutlineGroup rendering. We
/// don't render OutlineGroup recursively (children of a receipt are nil), but
/// keeping the model uniform makes the SwiftUI body shorter.
private struct DisplayNode: Identifiable {
    let id: String
    let approval: Approval?
    let receipt: Receipt?
    let children: [DisplayNode]
    var isLeaf: Bool { receipt != nil }
    var approvalID: String? { approval?.id }

    init(from node: ApprovalTreeNode) {
        switch node {
        case .approval(let approval, let receipts):
            self.id = "ap:\(approval.id)"
            self.approval = approval
            self.receipt = nil
            self.children = receipts.map { DisplayNode(receipt: $0) }
        case .unattached(let receipt):
            self.id = "or:\(receipt.id)"
            self.approval = nil
            self.receipt = receipt
            self.children = []
        }
    }

    private init(receipt: Receipt) {
        self.id = "r:\(receipt.id)"
        self.approval = nil
        self.receipt = receipt
        self.children = []
    }
}
