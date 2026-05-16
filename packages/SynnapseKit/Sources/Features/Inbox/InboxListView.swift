import SwiftUI
import Models
import DesignSystem

/// Inbox surface. macOS: three-column mail layout (folders / list / message).
/// iOS: `NavigationStack` with the list and a pushed detail screen.
///
/// Read-only in M7 — every interactive element here is a non-destructive
/// browse / inspect affordance. No compose, no reply, no send.
@MainActor
public struct InboxListView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: InboxListViewModel

    public init(viewModel: InboxListViewModel) {
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
            foldersSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            messageList
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
                .navigationTitle("Inbox")
        } detail: {
            messageDetail
        }
    }

    private var foldersSidebar: some View {
        let tokens = theme.tokens(for: scheme)
        return List(selection: Binding<SourceFolder?>(
            get: { viewModel.folder },
            set: { viewModel.selectFolder($0) }
        )) {
            // All folders entry — represented by `nil`.
            Button {
                viewModel.selectFolder(nil)
            } label: {
                folderRow(label: "All", count: viewModel.items.count, tokens: tokens)
            }
            .buttonStyle(.plain)

            Section("FOLDERS") {
                ForEach(SourceFolder.allCases, id: \.self) { folder in
                    folderRow(
                        label: folder.displayName,
                        count: viewModel.items.lazy.filter { $0.source == folder.source }.count,
                        tokens: tokens
                    )
                    .tag(folder)
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
            messageList
                .navigationTitle("Inbox")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        unreadBadge
                    }
                }
                .refreshable { await viewModel.refresh() }
                .navigationDestination(for: InboxItem.self) { item in
                    InboxMessageView(item: item)
                        .navigationBarTitleDisplayMode(.inline)
                        .onAppear { viewModel.select(item) }
                }
        }
    }

    @ViewBuilder
    private var unreadBadge: some View {
        let tokens = theme.tokens(for: scheme)
        if viewModel.unreadCount > 0 {
            Text("\(viewModel.unreadCount)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.accent.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(tokens.accent.color.opacity(0.5), lineWidth: 1)
                )
        }
    }
    #endif

    // MARK: - List

    @ViewBuilder
    private var messageList: some View {
        let tokens = theme.tokens(for: scheme)
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                tokens.surface.color
                ProgressView().tint(tokens.foregroundSecondary.color)
            }
            .accessibilityIdentifier("inbox.loading")
        case .empty:
            ZStack {
                tokens.surface.color
                VStack(spacing: 6) {
                    Text("Inbox is empty")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("Messages will appear as ingest runs.")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .accessibilityIdentifier("inbox.empty")
        case .results:
            messageListContent(tokens: tokens)
        case .error(let message):
            ZStack {
                tokens.surface.color
                VStack(spacing: 6) {
                    Text("Couldn't load inbox")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .accessibilityIdentifier("inbox.error")
        }
    }

    @ViewBuilder
    private func messageListContent(tokens: TokenSet) -> some View {
        let rows = viewModel.visibleItems
        #if os(iOS)
        List {
            ForEach(rows) { item in
                NavigationLink(value: item) {
                    InboxRow(item: item, isSelected: false)
                }
                .listRowBackground(tokens.surface.color)
            }
        }
        .scrollContentBackground(.hidden)
        .background(tokens.background.color)
        #else
        List(selection: Binding<InboxItem?>(
            get: { viewModel.selected },
            set: {
                if let v = $0 { viewModel.select(v) }
                else { viewModel.clearSelection() }
            }
        )) {
            ForEach(rows) { item in
                InboxRow(item: item, isSelected: viewModel.selected == item)
                    .tag(item)
            }
        }
        .listStyle(.inset)
        .background(tokens.surface.color)
        #endif
    }

    @ViewBuilder
    private var messageDetail: some View {
        let tokens = theme.tokens(for: scheme)
        if let selected = viewModel.selected {
            InboxMessageView(item: selected)
        } else {
            ZStack {
                tokens.background.color
                Text("Select a message")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    #if os(macOS)
    @ViewBuilder
    private func folderRow(label: String, count: Int, tokens: TokenSet) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }
    #endif
}

private struct InboxRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let item: InboxItem
    let isSelected: Bool

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(alignment: .top, spacing: 10) {
            // Unread dot — visible only when the item is unread; takes up a
            // fixed slot so read/unread rows align.
            Circle()
                .fill(item.isRead ? .clear : tokens.accent.color)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.senderDisplay)
                        .font(.system(size: 13, weight: item.isRead ? .regular : .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.source.rawValue)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Text(item.displaySubject)
                    .font(.system(size: 12, weight: item.isRead ? .regular : .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                Text(item.bodyPreview)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.senderDisplay + (item.isRead ? "" : ", unread"))
    }
}
