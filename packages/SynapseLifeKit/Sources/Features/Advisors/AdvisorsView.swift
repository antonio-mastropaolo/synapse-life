import SwiftUI
import Models
import DesignSystem

/// Advisors hub. macOS renders a 2-column `NavigationSplitView` (sidebar of
/// advisors + chat pane). iOS renders a `NavigationStack` rooted at a list
/// that pushes into per-advisor chat.
///
/// Identity: CockpitInstrument — the chat surface borrows the same dark
/// instrument tokens that drive the Finance hub so the app reads as a
/// single product.
@MainActor
public struct AdvisorsView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: AdvisorsListViewModel

    public init(viewModel: AdvisorsListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .task {
                if case .idle = viewModel.state { await viewModel.refresh() }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let advisor = viewModel.selectedAdvisor {
                ChatPane(viewModel: viewModel.chatViewModel(for: advisor))
                    .id(advisor.id)
            } else {
                placeholder
            }
        }
    }

    private var sidebar: some View {
        let tokens = theme.tokens(for: scheme)
        let advisors = viewModel.advisors
        return List(selection: Binding<String?>(
            get: { viewModel.selectedAdvisorId },
            set: { viewModel.select(advisorId: $0) }
        )) {
            Section {
                ForEach(advisors) { advisor in
                    AdvisorRow(advisor: advisor)
                        .tag(advisor.id)
                        .listRowBackground(tokens.surface.color)
                }
            } header: {
                Text("Advisors")
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(tokens.surface.color)
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    /// iOS layout. The outer `NavigationStack` lives in the tab shell
    /// (so deep links and tab-root reset behave correctly); this view
    /// only contributes content + `.navigationDestination`. Removing the
    /// inner `NavigationStack` also stops the double large-title that
    /// appeared on tab open in the previous iteration.
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack {
            tokens.background.color.ignoresSafeArea()
            switch viewModel.state {
            case .idle, .loading:
                ProgressView().tint(tokens.foregroundSecondary.color)
            case .error(let message):
                errorBody(message: message)
            case .ready(let advisors):
                List {
                    Section {
                        ForEach(advisors) { advisor in
                            NavigationLink(value: advisor.id) {
                                AdvisorRow(advisor: advisor)
                            }
                            .listRowBackground(tokens.surface.color)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationDestination(for: String.self) { advisorId in
            if let advisor = viewModel.advisors.first(where: { $0.id == advisorId }) {
                ChatPane(viewModel: viewModel.chatViewModel(for: advisor))
                    .navigationTitle(advisor.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .refreshable { await viewModel.refresh() }
    }
    #endif

    // MARK: - Common

    private var placeholder: some View {
        let tokens = theme.tokens(for: scheme)
        return ZStack {
            tokens.background.color
            VStack(spacing: 6) {
                Text("Select an advisor")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Pick a persona to start a thread")
                    .font(tokens.tickerFont(size: 11))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    private func errorBody(message: String) -> some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 6) {
            Text("Couldn't load advisors")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text(message)
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Advisor row

private struct AdvisorRow: View {
    let advisor: Advisor
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 10) {
            AdvisorAvatar(advisor: advisor, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(advisor.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                Text(advisor.specialty)
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if advisor.unreadCount > 0 {
                Text("\(advisor.unreadCount)")
                    .font(tokens.tickerFont(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.background.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tokens.accent.color)
                    .clipShape(Capsule())
                    .accessibilityLabel("\(advisor.unreadCount) unread")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AdvisorAvatar: View {
    let advisor: Advisor
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: advisor.avatarColorHex) ?? .gray)
            Text(advisor.avatarInitials)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Chat pane

@MainActor
public struct ChatPane: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: StreamingChatViewModel
    @FocusState private var composerFocused: Bool

    public init(viewModel: StreamingChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(spacing: 0) {
            header
            Divider().overlay(tokens.foregroundSecondary.color.opacity(0.18))
            transcript
            Divider().overlay(tokens.foregroundSecondary.color.opacity(0.18))
            composer
        }
        .background(tokens.background.color)
        .onDisappear { viewModel.cancel() }
    }

    private var header: some View {
        let tokens = theme.tokens(for: scheme)
        return HStack(spacing: 10) {
            AdvisorAvatar(advisor: viewModel.advisor, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.advisor.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(viewModel.advisor.specialty)
                    .font(tokens.tickerFont(size: 10))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
            if viewModel.isStreaming {
                Text("Streaming")
                    .font(tokens.tickerFont(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.accent.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tokens.accent.color.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tokens.surface.color)
    }

    private var transcript: some View {
        let tokens = theme.tokens(for: scheme)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if viewModel.messages.isEmpty {
                        emptyHint
                    } else {
                        ForEach(viewModel.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    if let err = viewModel.lastError {
                        Text(err)
                            .font(tokens.tickerFont(size: 10))
                            .foregroundStyle(tokens.lossAccent.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(tokens.background.color)
            #if os(iOS)
            // Drag-to-dismiss the keyboard while reviewing scrollback.
            // `.interactively` follows the gesture instead of dismissing
            // on the first downward delta — feels like Messages.app.
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 6) {
            Text("No messages yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Ask \(viewModel.advisor.name) about \(viewModel.advisor.specialty.lowercased()).")
                .font(tokens.tickerFont(size: 10))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var composer: some View {
        let tokens = theme.tokens(for: scheme)
        return HStack(alignment: .center, spacing: 10) {
            TextField("Message \(viewModel.advisor.name)", text: $viewModel.composer, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tokens.surface.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($composerFocused)
                .accessibilityLabel("Composer")
                .onSubmit { Task { await viewModel.send() } }
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? tokens.accent.color : tokens.foregroundSecondary.color.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tokens.surface.color)
    }

    private var canSend: Bool {
        !viewModel.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isStreaming
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: ChatMessage
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            HStack(alignment: .bottom, spacing: 0) {
                Text(displayContent)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isUser ? tokens.background.color : tokens.foregroundPrimary.color
                    )
                    .multilineTextAlignment(.leading)
                if message.isStreaming {
                    Text("▍")
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.accent.color)
                        .accessibilityLabel("Streaming")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? tokens.accent.color : tokens.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Advisor"): \(message.content)")
    }

    private var displayContent: String {
        // Show a single-space placeholder while the assistant message is
        // empty so the bubble doesn't collapse to zero height before the
        // first token lands.
        if message.content.isEmpty, message.isStreaming { return " " }
        return message.content
    }
}

// MARK: - Color hex bridge

extension Color {
    fileprivate init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
