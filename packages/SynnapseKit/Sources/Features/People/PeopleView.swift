import SwiftUI
import Models
import DesignSystem

/// People surface. macOS: `NavigationSplitView` with a search field at the
/// top of the sidebar and an avatar grid in the content column; the third
/// pane is the dossier. iOS: `NavigationStack` with a searchable list; tap
/// presents the dossier as a `.sheet`.
///
/// Read-only in M7 — operator can search, browse, and inspect; no compose
/// or edit affordances surface here.
@MainActor
public struct PeopleView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: PeopleViewModel
    @State private var iosDossierTarget: Person?

    public init(viewModel: PeopleViewModel) {
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
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
                .navigationTitle("People")
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 0) {
            searchField(tokens: tokens)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            Divider().opacity(0.2)
            sidebarList(tokens: tokens)
        }
        .background(tokens.surface.color)
    }

    @ViewBuilder
    private func sidebarList(tokens: TokenSet) -> some View {
        let rows = viewModel.searchText.isEmpty
            ? viewModel.people
            : viewModel.visiblePeople
        List(selection: Binding<Person?>(
            get: { viewModel.selected },
            set: { if let p = $0 { viewModel.select(p) } else { viewModel.clearSelection() } }
        )) {
            ForEach(rows) { person in
                PeopleSidebarRow(person: person, isSelected: viewModel.selected == person)
                    .tag(person)
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
            iosContent
                .navigationTitle("People")
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: Binding(
                        get: { viewModel.searchText },
                        set: { viewModel.queueSearch($0) }
                    ),
                    prompt: "Search people"
                )
                .refreshable { await viewModel.refresh() }
                .sheet(item: $iosDossierTarget) { person in
                    NavigationStack {
                        PersonDossierView(
                            person: person,
                            dossier: viewModel.lastDossier,
                            isLoading: viewModel.lastDossier == nil && viewModel.dossierError == nil,
                            error: viewModel.dossierError
                        )
                        .navigationTitle(person.displayName)
                        .navigationBarTitleDisplayMode(.inline)
                        .task { await viewModel.loadDossier(for: person.identity) }
                    }
                    .presentationDetents([.medium, .large])
                }
        }
    }

    @ViewBuilder
    private var iosContent: some View {
        let tokens = theme.tokens(for: scheme)
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                tokens.surface.color
                ProgressView().tint(tokens.foregroundSecondary.color)
            }
            .accessibilityIdentifier("people.loading")
        case .empty:
            emptyState(tokens: tokens)
        case .results:
            let rows = viewModel.searchText.isEmpty ? viewModel.people : viewModel.visiblePeople
            List {
                ForEach(rows) { person in
                    Button {
                        viewModel.select(person)
                        iosDossierTarget = person
                    } label: {
                        PeopleSidebarRow(person: person, isSelected: false)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(tokens.surface.color)
                }
            }
            .scrollContentBackground(.hidden)
            .background(tokens.background.color)
        case .error(let message):
            errorState(message, tokens: tokens)
        }
    }
    #endif

    // MARK: - Shared chunks

    @ViewBuilder
    private var content: some View {
        let tokens = theme.tokens(for: scheme)
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                tokens.surface.color
                ProgressView().tint(tokens.foregroundSecondary.color)
            }
            .accessibilityIdentifier("people.loading")
        case .empty:
            emptyState(tokens: tokens)
        case .results:
            let rows = viewModel.searchText.isEmpty ? viewModel.people : viewModel.visiblePeople
            PeopleAvatarGrid(
                people: rows,
                selected: viewModel.selected,
                onSelect: { viewModel.select($0) }
            )
            .background(tokens.surface.color)
        case .error(let message):
            errorState(message, tokens: tokens)
        }
    }

    @ViewBuilder
    private var detail: some View {
        let tokens = theme.tokens(for: scheme)
        if let selected = viewModel.selected {
            PersonDossierView(
                person: selected,
                dossier: viewModel.lastDossier,
                isLoading: viewModel.lastDossier == nil && viewModel.dossierError == nil,
                error: viewModel.dossierError
            )
            .task(id: selected.identity) {
                await viewModel.loadDossier(for: selected.identity)
            }
        } else {
            ZStack {
                tokens.background.color
                Text("Select a person")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }

    @ViewBuilder
    private func searchField(tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(tokens.foregroundSecondary.color)
                .font(.system(size: 11))
            TextField(
                "Search people",
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.queueSearch($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(tokens.foregroundPrimary.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tokens.background.color)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tokens.foregroundSecondary.color.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func emptyState(tokens: TokenSet) -> some View {
        ZStack {
            tokens.surface.color
            VStack(spacing: 6) {
                Text("No people")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Inbox sync will surface senders here.")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .accessibilityIdentifier("people.empty")
    }

    @ViewBuilder
    private func errorState(_ message: String, tokens: TokenSet) -> some View {
        ZStack {
            tokens.surface.color
            VStack(spacing: 6) {
                Text("Couldn't load people")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .accessibilityIdentifier("people.error")
    }
}

// MARK: - Avatar grid (macOS content column)

private struct PeopleAvatarGrid: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let people: [Person]
    let selected: Person?
    let onSelect: (Person) -> Void

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 116, maximum: 144), spacing: 12)
    ]

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(people) { person in
                    Button {
                        onSelect(person)
                    } label: {
                        AvatarTile(
                            person: person,
                            isSelected: selected == person,
                            tokens: tokens
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

private struct AvatarTile: View {
    let person: Person
    let isSelected: Bool
    let tokens: TokenSet

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tokens.background.color)
                Text(initials(of: person.displayName))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .frame(width: 64, height: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected
                            ? tokens.accent.color
                            : tokens.foregroundSecondary.color.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            Text(person.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            if person.openActions > 0 || person.awaitingMyReply > 0 {
                Text("\(person.openActions + person.awaitingMyReply) open")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(tokens.accent.color)
            } else {
                Text(person.kind == .entity ? "entity" : " ")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(tokens.surface.color)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tokens.foregroundSecondary.color.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(person.displayName)
        .accessibilityHint(person.identity)
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ")
        let chars: [Character] = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }
}

// MARK: - Sidebar row (macOS sidebar + iOS list)

private struct PeopleSidebarRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let person: Person
    let isSelected: Bool

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tokens.background.color)
                Text(initials(of: person.displayName))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .stroke(tokens.foregroundSecondary.color.opacity(0.18), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .lineLimit(1)
                Text(person.identity)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if person.openActions > 0 || person.awaitingMyReply > 0 {
                Text("\(person.openActions + person.awaitingMyReply)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.accent.color)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ")
        let chars: [Character] = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }
}
